require "rails_helper"

RSpec.describe Brainstorm::Planner do
  subject(:planner) { described_class.new(project) }

  let(:root) { Pathname.new(Dir.mktmpdir("planner-spec")) }
  let(:project) { Project.new(id: 987_654, name: "Spec project", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }
  let(:dir) { root.join("987654") }
  let(:lifecycle) { instance_double(Brainstorm::RunLifecycle, running?: false, last_started_at: nil, start: true, poll: nil) }

  before do
    stub_const("Brainstorm::Planner::ROOT", root)
    allow(Brainstorm::RunLifecycle).to receive(:new).with(dir: dir, stale_after: 45.minutes).and_return(lifecycle)
  end

  after { FileUtils.remove_entry(root) if root.to_s.start_with?(Dir.tmpdir) }

  describe "run orchestration" do
    it "supplies project prompt and history inputs to the lifecycle when starting" do
      expect(planner.start).to be(true)

      expect(lifecycle).to have_received(:start) do |**inputs|
        expect(inputs[:prepare]).to be_a(Method)
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
        expect(inputs[:prepare]).to be_a(Method)
        expect(inputs[:cwd]).to eq(root.to_s)
        expect(inputs[:allowed_tools]).to eq(described_class::ALLOWED_TOOLS)
      end
    end
  end
end
