require "rails_helper"

RSpec.describe Brainstorm::Planner do
  subject(:planner) { described_class.new(project) }

  let(:root) { Pathname.new(Dir.mktmpdir("planner-spec")) }
  let(:project) { Project.new(id: 987_654, name: "Spec project", kind: :personal, local_directory: root.to_s, brainstorm_goal: "improve things") }
  let(:dir) { root.join("987654") }
  let(:aborted_event) { '{"type":"result","subtype":"error_during_execution","terminal_reason":"aborted_streaming","is_error":true}' }

  before do
    stub_const("Brainstorm::Planner::ROOT", root)
    FileUtils.mkdir_p(dir)
    dir.join("pid").write("123")
    dir.join("started_at").write(Time.current.to_f)
    allow(AiCli::Runner).to receive(:poll).with(123).and_return([ :completed, nil ])
  end

  after { FileUtils.remove_entry(root) if root.to_s.start_with?(Dir.tmpdir) }

  describe "#poll when the agent wrote no result.json" do
    it "retries once when the stream was aborted" do
      dir.join("agent.log").write("#{aborted_event}\n")
      allow(AiCli::Runner).to receive(:start).and_return(456)

      expect(planner.poll).to be_nil
      expect(AiCli::Runner).to have_received(:start).once
      expect(dir.join("pid").read).to eq("456")
      expect(dir.join("retried")).to exist
    end

    it "fails with the terminal reason after the retry was used" do
      dir.join("agent.log").write("#{aborted_event}\n")
      FileUtils.touch(dir.join("retried"))

      expect { planner.poll }.to raise_error(Brainstorm::FetchError, /error_during_execution\/aborted_streaming/)
    end

    it "fails without retrying when there is no result event" do
      dir.join("agent.log").write("some plain output\n")
      allow(AiCli::Runner).to receive(:start)

      expect { planner.poll }.to raise_error(Brainstorm::FetchError, /no result event in the log/)
      expect(AiCli::Runner).not_to have_received(:start)
    end
  end

  describe "#start" do
    it "truncates the previous log and clears the retry marker" do
      dir.join("agent.log").write("old run")
      FileUtils.touch(dir.join("retried"))
      allow(AiCli::Runner).to receive(:start).and_return(789)

      expect(planner.start).to be(true)
      expect(dir.join("agent.log").read).to eq("")
      expect(dir.join("retried")).not_to exist
    end
  end
end
