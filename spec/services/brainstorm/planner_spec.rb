require "rails_helper"

RSpec.describe Brainstorm::Planner do
  subject(:planner) { described_class.new(project, root: root, lifecycle: lifecycle) }

  let(:root) { Pathname.new(Dir.mktmpdir("planner-spec")) }
  let(:project) { Project.new(id: 987_654, name: "Spec project", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }
  let(:dir) { root.join("987654") }
  let(:lifecycle) { instance_double(Brainstorm::RunLifecycle, running?: false, last_started_at: nil, start: true, poll: nil, result_path: dir.join("result.json")) }

  after { FileUtils.remove_entry(root) if root.to_s.start_with?(Dir.tmpdir) }

  describe ".model" do
    it "defaults brainstorms to gpt-6-sol" do
      expect(described_class.model).to eq("gpt-6-sol")
    end
  end

  describe "#wait_reason" do
    let(:project) { Project.create!(name: "Planner spec #{SecureRandom.hex(4)}", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }

    def add_workflow(**attrs)
      project.workflows.create!({ task_description: "do it", branch_name: "b-#{SecureRandom.hex(3)}", github_reviewer: "someone" }.merge(attrs))
    end

    it "is nil when nothing is pending" do
      expect(planner.wait_reason).to be_nil
    end

    it "names the number of pending development workflows" do
      2.times { add_workflow(status: :pending) }

      expect(planner.wait_reason).to eq("2 workflow(s) still pending; start or delete them first.")
    end

    it "ignores implementing and runbook workflows" do
      add_workflow(status: :implementing)
      add_workflow(kind: :runbook, status: :pending)

      expect(planner.wait_reason).to be_nil
    end
  end

  describe "#record_start!" do
    let(:project) { Project.create!(name: "Planner spec #{SecureRandom.hex(4)}", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }

    it "stamps brainstorm_last_run_at with the current time" do
      freeze_time do
        planner.record_start!

        expect(project.reload.brainstorm_last_run_at).to eq(Time.current)
      end
    end

    it "uses an injected clock" do
      at = Time.zone.local(2026, 1, 2, 3, 4, 5)
      clock = double("clock", current: at)

      described_class.new(project, clock: clock, root: root, lifecycle: lifecycle).record_start!

      expect(project.reload.brainstorm_last_run_at).to eq(at)
    end
  end

  describe "run orchestration" do
    it "supplies project prompt and history inputs to the lifecycle when starting" do
      expect(planner.start).to be(true)

      expect(lifecycle).to have_received(:start) do |**inputs|
        expect(inputs[:prepare]).to respond_to(:call)
        FileUtils.mkdir_p(dir)
        inputs[:prepare].call
        expect(inputs[:cwd]).to eq(root.to_s)
        expect(inputs[:allowed_tools]).to eq(described_class::ALLOWED_TOOLS)
        expect(inputs[:model]).to eq(described_class.model)
        expect(inputs[:effort]).to eq(described_class.effort)
        expect(inputs[:prompt]).to include("improve things", dir.join("result.json").to_s)
      end
      expect(dir.join("history.md").read).to eq("")
    end

    it "normalizes completed rows returned by the lifecycle" do
      raw_rows = [ { "summary" => "  Add tests ", "task" => "Cover the lifecycle" } ]
      allow(lifecycle).to receive(:poll).and_yield(raw_rows).and_return([ { "summary" => "Add tests", "task" => "Cover the lifecycle" } ])

      expect(planner.poll).to eq([ { "summary" => "Add tests", "task" => "Cover the lifecycle" } ])
      expect(lifecycle).to have_received(:poll) do |**inputs|
        expect(inputs[:prepare]).to respond_to(:call)
        expect(inputs[:cwd]).to eq(root.to_s)
        expect(inputs[:allowed_tools]).to eq(described_class::ALLOWED_TOOLS)
      end
    end
  end

  describe "launch snapshot" do
    let(:dir) { root.join(project.id.to_s) }
    let(:project) { Project.create!(name: "Planner spec #{SecureRandom.hex(4)}", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }

    def add_implementing(summary)
      project.workflows.create!(task_description: summary, summary: summary, branch_name: "b-#{SecureRandom.hex(3)}", github_reviewer: "someone", status: :implementing)
    end

    def launched_inputs
      inputs = nil
      allow(lifecycle).to receive(:start) { |**kw| inputs = kw; FileUtils.mkdir_p(dir); kw[:prepare].call; true }
      planner.start
      inputs
    end

    it "derives prompt, total and history from one newest-first read, capping inline lines at 30" do
      35.times { |i| add_implementing("Item #{format('%02d', i)}") }

      inputs = launched_inputs
      history = dir.join("history.md").read.split("\n")

      expect(history.size).to eq(35)
      expect(history.first).to include("Item 34")
      expect(history.last).to include("Item 00")
      prompt = inputs[:prompt]
      expect(prompt).to include(history.first, history[29])
      expect(prompt).not_to include(history[30])
      expect(prompt).to include("5 older ones are in #{dir.join('history.md')}")
    end

    it "reads the workflows once per attempt so a change between reads cannot split them" do
      3.times { |i| add_implementing("Item #{i}") }
      relation = project.workflows.development.where(status: :implementing).order(id: :desc)
      allow(planner).to receive(:in_flight).and_wrap_original do |m|
        result = m.call.load
        add_implementing("Late arrival") # lands after the snapshot's read
        result
      end

      inputs = launched_inputs

      expect(dir.join("history.md").read.split("\n").size).to eq(3)
      expect(inputs[:prompt]).not_to include("Late arrival", "older ones")
      expect(relation.count).to eq(4)
    end

    it "takes a fresh snapshot on each poll attempt" do
      add_implementing("First")
      allow(lifecycle).to receive(:poll) { |**kw| kw[:prompt] }
      first = planner.poll
      add_implementing("Second")
      second = planner.poll

      expect(first).to include("First")
      expect(first).not_to include("Second")
      expect(second).to include("Second")
    end
  end
end
