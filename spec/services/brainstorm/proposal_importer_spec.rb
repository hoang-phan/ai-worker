require "rails_helper"

RSpec.describe Brainstorm::ProposalImporter do
  let(:local_directory) { Dir.mktmpdir("importer-spec") }
  let(:suffix) { SecureRandom.hex(4) }
  let(:project) do
    Project.create!(name: "Importer spec #{suffix}", kind: :personal, local_directory: local_directory,
                    brainstorm_goal: "improve things", brainstorm_max_workflows: 2, default_skills: "ruby")
  end
  let(:in_flight) { project.workflows.development.where(status: :implementing) }
  let(:importer) { described_class.new(project, in_flight: in_flight) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  def proposal(summary, task = "Do it")
    { "summary" => summary, "task" => task }
  end

  it "is the struct Planner exposes as Result" do
    expect(Brainstorm::Planner::Result).to equal(described_class::Result)
  end

  it "creates pending workflows with default skills and increasing positions" do
    result = importer.call([ proposal("Alpha #{suffix}"), proposal("Beta #{suffix}") ])

    expect(result.created).to eq([ "Alpha #{suffix}", "Beta #{suffix}" ])
    expect(result.skipped).to eq([])
    workflows = project.workflows.order(:position)
    expect(workflows.map(&:status).uniq).to eq([ "pending" ])
    expect(workflows.map(&:skills).uniq).to eq([ "ruby" ])
    expect(workflows.map(&:task_description)).to eq([ "Do it", "Do it" ])
    expect(workflows.map(&:position)).to eq([ 1, 2 ])
  end

  it "creates implementing workflows when auto start is on" do
    project.update!(brainstorm_auto_start: true)

    importer.call([ proposal("Auto #{suffix}") ])

    expect(project.workflows.pluck(:status)).to eq([ "implementing" ])
  end

  it "does nothing while a workflow is queued" do
    project.workflows.create!(summary: "Manual #{suffix}", task_description: "x", status: :pending, position: 1)

    result = importer.call([ proposal("New #{suffix}") ])

    expect(result.created).to eq([])
    expect(result.skipped).to eq([])
    expect(project.workflows.count).to eq(1)
  end

  it "stops at the project's maximum created" do
    result = importer.call([ proposal("One #{suffix}"), proposal("Two #{suffix}"), proposal("Three #{suffix}") ])

    expect(result.created.size).to eq(2)
    expect(result.skipped).to eq([])
    expect(project.workflows.count).to eq(2)
  end

  it "skips proposals matching an in-flight workflow's brief after normalizing" do
    project.workflows.create!(summary: "Add  the Widget! #{suffix}", task_description: "x", status: :implementing, position: 1)

    result = importer.call([ proposal("add the widget #{suffix}"), proposal("Other #{suffix}") ])

    expect(result.skipped).to eq([ "add the widget #{suffix}" ])
    expect(result.created).to eq([ "Other #{suffix}" ])
  end

  it "skips a proposal repeating an earlier one in the batch" do
    result = importer.call([ proposal("Same #{suffix}"), proposal("SAME, #{suffix}") ])

    expect(result.created).to eq([ "Same #{suffix}" ])
    expect(result.skipped).to eq([ "SAME, #{suffix}" ])
  end

  it "does not count skipped duplicates towards the maximum" do
    project.workflows.create!(summary: "Known #{suffix}", task_description: "x", status: :implementing, position: 1)

    result = importer.call([ proposal("Known #{suffix}"), proposal("A #{suffix}"), proposal("B #{suffix}") ])

    expect(result.created).to eq([ "A #{suffix}", "B #{suffix}" ])
  end

  it "reports failed saves in skipped with their error messages" do
    result = importer.call([ proposal("Broken #{suffix}", ""), proposal("Fine #{suffix}") ])

    expect(result.created).to eq([ "Fine #{suffix}" ])
    expect(result.skipped.size).to eq(1)
    expect(result.skipped.first).to start_with("Broken #{suffix} (").and include("Task description")
  end


  describe "Result#summary" do
    it "counts created and skipped" do
      result = described_class::Result.new(created: [ 1, 2 ], skipped: [ "a" ])

      expect(result.summary).to eq("created 2, skipped 1")
    end
  end
end
