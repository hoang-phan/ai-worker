require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::Capacity do
  let(:dirs) { [ make_tmpdir("capacity-spec"), make_tmpdir("capacity-spec"), make_tmpdir("capacity-spec") ] }

  def workflow_for(dir)
    Workflow.new(project: Project.new(local_directory: dir))
  end

  it "cannot start once all agent slots are occupied" do
    busy_clones = [ Scheduling::Planner.clone_key(Project.new(local_directory: dirs[0])) ]
    capacity = described_class.new(busy_clones: busy_clones, max: 1)

    expect(capacity.can_start?(workflow_for(dirs[1]))).to be false
  end

  it "treats differently spelled paths to one clone as busy" do
    capacity = described_class.new(
      busy_clones: [ Scheduling::Planner.clone_key(Project.new(local_directory: dirs[0])) ],
      max: 2
    )

    expect(capacity.can_start?(workflow_for("#{dirs[0]}/./"))).to be false
  end

  it "occupies both the clone and an agent slot when a workflow starts" do
    capacity = described_class.new(busy_clones: [], max: 2)
    first = workflow_for(dirs[0])

    capacity.started!(first)

    expect(capacity.active_count).to eq(1)
    expect(capacity.can_start?(workflow_for("#{dirs[0]}/"))).to be false
    capacity.started!(workflow_for(dirs[1]))
    expect(capacity.can_start?(workflow_for(dirs[2]))).to be false
  end

  it "does not mutate the initial busy clone list" do
    initial_busy_clones = [ Scheduling::Planner.clone_key(Project.new(local_directory: dirs[0])) ]
    capacity = described_class.new(busy_clones: initial_busy_clones, max: 3)

    capacity.started!(workflow_for(dirs[1]))

    expect(initial_busy_clones).to eq([ Scheduling::Planner.clone_key(Project.new(local_directory: dirs[0])) ])
  end
end
