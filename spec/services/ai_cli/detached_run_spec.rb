require "rails_helper"

RSpec.describe AiCli::DetachedRun do
  let(:error_class) { Class.new(StandardError) }
  let(:tmp) { Dir.mktmpdir("detached_run") }
  let(:dir) { Pathname(tmp).join("run") }
  let(:run) { described_class.new(dir: dir, result_name: "result.json", stale_after: 15.minutes, error_class: error_class) }

  after { FileUtils.remove_entry(tmp) }

  def start_run
    allow(AiCli::Runner).to receive(:start).and_return(4242)
    run.start(cwd: tmp, prompt: "go")
  end

  describe "#start" do
    it "writes pid and started_at and deletes an old result" do
      FileUtils.mkdir_p(dir)
      dir.join("result.json").write("[]")

      expect(AiCli::Runner).to receive(:start)
        .with(tmp, "go", log_path: dir.join("agent.log").to_s, allowed_tools: [ "Write" ]).and_return(4242)

      expect(run.start(cwd: tmp, prompt: "go", allowed_tools: [ "Write" ])).to be(true)
      expect(dir.join("pid").read).to eq("4242")
      expect(run.last_started_at).to be_within(5.seconds).of(Time.current)
      expect(dir.join("result.json")).not_to exist
    end

    it "passes model and effort through to the runner" do
      expect(AiCli::Runner).to receive(:start)
        .with(tmp, "go", log_path: dir.join("agent.log").to_s, allowed_tools: nil, model: "opus", effort: "high").and_return(1)

      expect(run.start(cwd: tmp, prompt: "go", model: "opus", effort: "high")).to be(true)
    end

    it "exposes the log path" do
      expect(run.log_path).to eq(dir.join("agent.log"))
    end

    it "does nothing while a process is running" do
      start_run
      allow(AiCli::Runner).to receive(:poll).with(4242).and_return(:running)
      expect(AiCli::Runner).not_to receive(:start)

      expect(run.start(cwd: tmp, prompt: "go")).to be(false)
    end
  end

  describe "#poll" do
    it "returns nil when nothing was started" do
      expect(run.poll).to be_nil
      expect(run).not_to be_running
    end

    it "returns nil while running and not stale" do
      start_run
      allow(AiCli::Runner).to receive(:poll).with(4242).and_return(:running)

      expect(run).to be_running
      expect(run.poll).to be_nil
      expect(dir.join("pid")).to exist
    end

    it "raises and clears the pid when stale" do
      start_run
      dir.join("started_at").write(1.hour.ago.to_f)
      allow(AiCli::Runner).to receive(:poll).with(4242).and_return(:running)

      expect { run.poll }.to raise_error(error_class, /did not finish/)
      expect(dir.join("pid")).not_to exist
    end

    context "when the process finished" do
      before do
        start_run
        allow(AiCli::Runner).to receive(:poll).with(4242).and_return([ :completed, nil ])
      end

      it "parses an array, clears the pid and yields rows to the block" do
        dir.join("result.json").write('[{"a":1}]')

        expect(run.poll).to eq([ { "a" => 1 } ])
        expect(dir.join("pid")).not_to exist
      end

      it "returns the block result" do
        dir.join("result.json").write("[1,2]")
        expect(run.poll { |rows| rows.sum }).to eq(3)
      end

      it "raises when the result file is missing" do
        expect { run.poll }.to raise_error(error_class, /wrote no result.json/)
      end

      it "raises when the result is not an array" do
        dir.join("result.json").write('{"a":1}')
        expect { run.poll }.to raise_error(error_class, /not a JSON array/)
      end

      it "raises on invalid JSON" do
        dir.join("result.json").write("nope")
        expect { run.poll }.to raise_error(error_class, /invalid JSON/)
      end
    end
  end
end
