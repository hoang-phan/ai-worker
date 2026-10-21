require "rails_helper"

RSpec.describe Projects::WorkflowReorder do
  let(:local_directory) { Dir.mktmpdir("workflow-reorder-spec") }
  let(:project) { Project.create!(name: "Reorder spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:other_project) { Project.create!(name: "Reorder spec other", kind: :jira, repo_full_name: "org/other", local_directory: Dir.mktmpdir("workflow-reorder-other")) }
  let!(:first) { project.workflows.create!(jira_ticket: "REORDER-1", branch_name: "reorder-1", github_reviewer: "x", position: 1) }
  let!(:second) { project.workflows.create!(jira_ticket: "REORDER-2", branch_name: "reorder-2", github_reviewer: "x", position: 2) }
  let!(:third) { project.workflows.create!(jira_ticket: "REORDER-3", branch_name: "reorder-3", github_reviewer: "x", position: 3) }

  after do
    [ local_directory, other_project.local_directory ].each do |dir|
      FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir)
    end
  end

  def ordered_ids = project.workflows.order(:position, :id).pluck(:id)

  it "moves a workflow up" do
    expect(described_class.new(project).move(third, :up)).to be(true)
    expect(ordered_ids).to eq([ first.id, third.id, second.id ])
  end

  it "moves a workflow down, accepting a string direction" do
    expect(described_class.new(project).move(first, "down")).to be(true)
    expect(ordered_ids).to eq([ second.id, first.id, third.id ])
  end

  it "renumbers duplicate positions to 1..n" do
    second.update_columns(position: 1)
    third.update_columns(position: 1)

    expect(described_class.new(project).move(third, :up)).to be(true)

    expect(ordered_ids).to eq([ first.id, third.id, second.id ])
    expect(project.workflows.order(:position, :id).pluck(:position)).to eq([ 1, 2, 3 ])
  end

  it "returns false at the top and leaves positions alone" do
    expect(described_class.new(project).move(first, :up)).to be(false)
    expect(project.workflows.order(:id).pluck(:position)).to eq([ 1, 2, 3 ])
  end

  it "returns false at the bottom and leaves positions alone" do
    expect(described_class.new(project).move(third, :down)).to be(false)
    expect(project.workflows.order(:id).pluck(:position)).to eq([ 1, 2, 3 ])
  end

  it "returns false for a workflow from another project and changes nothing" do
    foreign = other_project.workflows.create!(jira_ticket: "REORDER-X", branch_name: "reorder-x", github_reviewer: "x", position: 2)

    expect(described_class.new(project).move(foreign, :up)).to be(false)
    expect(project.workflows.order(:id).pluck(:position)).to eq([ 1, 2, 3 ])
    expect(foreign.reload.position).to eq(2)
  end
end
