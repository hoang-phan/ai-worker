require "rails_helper"

RSpec.describe AiCli::RunLogs do
  let(:dir) { Dir.mktmpdir("run-logs-spec") }

  after { FileUtils.remove_entry(dir) }

  describe ".new_path" do
    it "builds workflow-<id>-<unix>.log under the dir" do
      path = described_class.new_path(7, at: Time.at(1_700_000_000), dir: dir)

      expect(path).to eq(File.join(dir, "workflow-7-1700000000.log"))
    end

    it "defaults to DIR and the current time" do
      freeze_time do
        expect(described_class.new_path(7)).to eq(File.join(described_class::DIR, "workflow-7-#{Time.current.to_i}.log"))
      end
    end
  end

  describe ".latest" do
    def touch_log(name, mtime)
      path = File.join(dir, name)
      File.write(path, "")
      File.utime(Time.at(mtime), Time.at(mtime), path)
      path
    end

    it "picks the newest log by mtime" do
      touch_log("workflow-1-100.log", 100)
      recent = touch_log("workflow-1-50.log", 200)

      expect(described_class.latest(1, dir: dir)).to eq(recent)
    end

    it "does not confuse workflow 1 with workflow 12" do
      one = touch_log("workflow-1-100.log", 100)
      touch_log("workflow-12-200.log", 200)

      expect(described_class.latest(1, dir: dir)).to eq(one)
      expect(described_class.latest(12, dir: dir)).to eq(File.join(dir, "workflow-12-200.log"))
    end

    it "returns nil when there is no log" do
      expect(described_class.latest(1, dir: dir)).to be_nil
    end
  end
end
