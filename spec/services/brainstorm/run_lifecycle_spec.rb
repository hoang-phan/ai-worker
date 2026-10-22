require "rails_helper"

RSpec.describe Brainstorm::RunLifecycle do
  let(:root) { Pathname.new(Dir.mktmpdir("brainstorm-run-lifecycle-spec")) }
  let(:dir) { root.join("run") }
  let(:runner) { instance_double(AiCli::Runner.singleton_class) }
  let(:lifecycle) { described_class.new(dir: dir, stale_after: 45.minutes, runner: runner) }
  let(:launch_inputs) { { cwd: root.to_s, prompt: "brainstorm", allowed_tools: [ "Read" ], model: "opus", effort: "high" } }
  let(:aborted_event) { '{"type":"result","subtype":"error_during_execution","terminal_reason":"aborted_streaming","is_error":true}' }

  before do
    FileUtils.mkdir_p(dir)
    dir.join("pid").write("123")
    dir.join("started_at").write(Time.current.to_f)
    allow(runner).to receive(:poll).with(123).and_return([ :completed, nil ])
  end

  after { FileUtils.remove_entry(root) if root.to_s.start_with?(Dir.tmpdir) }

  describe "#result_path" do
    it "is the detached run's result file inside the run directory" do
      expect(lifecycle.result_path).to eq(dir.join("result.json"))
    end
  end

  describe "#poll when the agent wrote no result.json" do
    it "retries once when the stream was aborted" do
      dir.join("agent.log").write("#{aborted_event}\n")
      allow(runner).to receive(:start).and_return(456)

      expect(lifecycle.poll(**launch_inputs)).to be_nil
      expect(runner).to have_received(:start).with(
        root.to_s, "brainstorm", log_path: dir.join("agent.log").to_s,
        allowed_tools: [ "Read" ], model: "opus", effort: "high"
      ).once
      expect(dir.join("pid").read).to eq("456")
      expect(dir.join("retried")).to exist
    end

    it "keeps the terminal reason after the retry was used" do
      dir.join("agent.log").write("#{aborted_event}\n")
      FileUtils.touch(dir.join("retried"))

      expect { lifecycle.poll(**launch_inputs) }
        .to raise_error(Brainstorm::FetchError, /error_during_execution\/aborted_streaming/)
    end

    it "fails without retrying when there is no result event" do
      dir.join("agent.log").write("some plain output\n")
      allow(runner).to receive(:start)

      expect { lifecycle.poll(**launch_inputs) }.to raise_error(Brainstorm::FetchError, /no result event in the log/)
      expect(runner).not_to have_received(:start)
    end
  end

  describe "#poll with result.json" do
    it "keeps DetachedRun as the result-file owner and yields its parsed rows" do
      dir.join("result.json").write('[{"summary":"Add lifecycle specs"}]')

      expect(lifecycle.poll(**launch_inputs) { |rows| rows.map { |row| row.fetch("summary") } })
        .to eq([ "Add lifecycle specs" ])
      expect(dir.join("pid")).not_to exist
    end
  end

  describe "#start" do
    it "truncates the previous log, clears the retry marker, and preserves the detached result contract" do
      dir.join("agent.log").write("old run")
      dir.join("result.json").write("[]")
      FileUtils.touch(dir.join("retried"))
      allow(runner).to receive(:start).and_return(789)

      expect(lifecycle.start(**launch_inputs)).to be(true)
      expect(dir.join("agent.log").read).to eq("")
      expect(dir.join("retried")).not_to exist
      expect(dir.join("result.json")).not_to exist
      expect(dir.join("pid").read).to eq("789")
    end
  end
end
