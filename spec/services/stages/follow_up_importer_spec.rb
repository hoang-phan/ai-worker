require "rails_helper"

RSpec.describe Stages::FollowUpImporter, type: :service do
  let_personal_project("follow-up-importer-spec", default_skills: "ruby")
  let!(:current) { build_task_workflow(project, status: :implementing) }

  def proposals(*summaries) = summaries.map { |summary| { "summary" => summary, "task" => "Task for #{summary}" } }

  def call(*summaries) = described_class.new(project).call(proposals(*summaries))

  def follow_ups = project.workflows.where.not(id: current.id).order(:id)

  it "creates pending development workflows with default skills and the next position, returning the summaries" do
    expect(call("Fix A")).to eq [ "Fix A" ]

    expect(follow_ups.map { |w| [ w.summary, w.task_description, w.status, w.kind, w.skills ] })
      .to eq([ [ "Fix A", "Task for Fix A", "pending", "development", "ruby" ] ])
    expect(follow_ups.first.position).to be > current.position
  end

  it "creates at most 2" do
    expect(call("Fix A", "Fix B", "Fix C")).to eq [ "Fix A", "Fix B" ]
    expect(follow_ups.map(&:summary)).to eq [ "Fix A", "Fix B" ]
  end

  it "skips duplicates within the batch" do
    expect(call("Fix A", "fix a!", "Fix B")).to eq [ "Fix A", "Fix B" ]
  end

  it "skips summaries matching an existing non-done workflow, but not a done one" do
    build_task_workflow(project, summary: "fix a!", status: :pending)
    build_task_workflow(project, summary: "Fix B", status: :done)

    expect(call("Fix A", "Fix B")).to eq [ "Fix B" ]
  end

  it "skips a proposal that fails to save" do
    batch = proposals("Fix A", "Fix B") + [ { "summary" => "No task", "task" => "" } ]
    batch[1]["task"] = ""

    expect(described_class.new(project).call(batch)).to eq [ "Fix A" ]
    expect(follow_ups.map(&:summary)).to eq [ "Fix A" ]
  end
end
