require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::PostMergePhase do
  let(:directories) { [] }
  let(:executed) { [] }
  let(:merged_urls) { [] }
  let(:failing_pr_urls) { [] }
  let(:logger) { instance_double(Logger, error: nil) }
  let(:execute) { ->(workflow) { executed << workflow.id } }
  let(:github) do
    double("github").tap do |client| # rubocop:disable RSpec/VerifiedDoubles
      allow(client).to receive(:merged?) do |url|
        raise "github down" if failing_pr_urls.include?(url)

        merged_urls << url
        false
      end
    end
  end
  let(:github_factory) { ->(_project) { github } }
  let(:phase) { described_class.new(execute: execute, github_factory: github_factory, logger: logger) }

  after do
    directories.each { |d| FileUtils.remove_entry(d) if d.start_with?(Dir.tmpdir) && File.exist?(d) }
  end

  def project(kind: :jira)
    directory = Dir.mktmpdir("post-merge-phase-spec")
    directories << directory
    attrs = { name: "Post merge spec #{SecureRandom.hex(4)}", kind: kind, local_directory: directory }
    attrs[:repo_full_name] = "acme/widgets" if kind == :jira
    Project.create!(**attrs)
  end

  def workflow(project: self.project, status: :done, position: 1, **attrs)
    if project.jira?
      attrs.reverse_merge!(jira_ticket: "SPEC-#{SecureRandom.random_number(10_000)}", branch_name: "spec-#{SecureRandom.hex(4)}", github_reviewer: "reviewer")
    else
      attrs[:task_description] ||= "Task #{SecureRandom.hex(4)}"
    end
    project.workflows.create!(status: status, kind: :development, position: position, **attrs)
  end

  def done_workflow(position: 1, **attrs)
    url = "https://github.com/acme/widgets/pull/#{SecureRandom.random_number(100_000)}"
    workflow(status: :done, position: position, github_pr_url: url, **attrs).tap do |wf|
      wf.stages.create!(stage_type: :pr_check)
    end
  end

  it "is skipped while work is in progress" do
    workflow(status: :implementing, processing: true)
    done_workflow
    merged = workflow(status: :merged)

    phase.call

    expect(merged_urls).to be_empty
    expect(executed).not_to include(merged.id)
  end

  it "only checks jira-tracked done workflows that have a pr_check stage" do
    tracked = done_workflow(position: 1)
    done_workflow(position: 2, project: project(kind: :personal))
    no_stage = workflow(status: :done, position: 3, github_pr_url: "https://github.com/acme/widgets/pull/999")
    no_stage.stages.pr_check.destroy_all

    phase.call

    expect(merged_urls).to eq([ tracked.github_pr_url ])
  end

  it "builds the github client for the workflow's project" do
    done = done_workflow
    projects = []
    factory = lambda do |project|
      projects << project
      github
    end

    described_class.new(execute: execute, github_factory: factory, logger: logger).call

    expect(projects).to eq([ done.project ])
  end

  it "logs a raising merge check and continues with the rest" do
    failing = done_workflow(position: 1)
    following = done_workflow(position: 2)
    failing_pr_urls << failing.github_pr_url

    phase.call

    expect(logger).to have_received(:error).with(/\[scheduler\] merge check workflow=#{failing.id} RuntimeError: github down/)
    expect(merged_urls).to eq([ following.github_pr_url ])
  end

  it "executes only the first merged workflow" do
    first = workflow(status: :merged, position: 1)
    second = workflow(status: :merged, position: 2)

    phase.call

    expect(executed).to eq([ first.id ])
    expect(executed).not_to include(second.id)
  end

  it "logs an executor failure" do
    merged = workflow(status: :merged)
    failing = described_class.new(execute: ->(_workflow) { raise "boom" }, github_factory: github_factory, logger: logger)

    failing.call

    expect(logger).to have_received(:error).with("[scheduler] workflow=#{merged.id} RuntimeError: boom")
  end
end
