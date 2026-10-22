require "rails_helper"

RSpec.describe Prompts::SubagentRoster do
  let(:directory) { Dir.mktmpdir("subagent-roster-spec") }
  let(:agents_dir) { File.join(directory, ".claude", "agents") }

  after { FileUtils.remove_entry(directory) }

  def write_agent(file, content)
    FileUtils.mkdir_p(agents_dir)
    File.write(File.join(agents_dir, file), content)
  end

  it "returns [] when the directory has no agents" do
    expect(described_class.new(directory).entries).to eq([])
  end

  it "returns [] for a blank directory" do
    expect(described_class.new(nil).entries).to eq([])
  end

  it "reads name and description, sorted by name" do
    write_agent("b.md", "---\nname: spec-writer\ndescription: Writes\n  specs\n---\nBody")
    write_agent("a.md", "---\nname: reviewer\ndescription: Reviews diffs\n---\nBody")

    expect(described_class.new(directory).entries).to eq([
      { name: "reviewer", description: "Reviews diffs" },
      { name: "spec-writer", description: "Writes specs" }
    ])
  end

  it "ignores files without a name, without frontmatter or with malformed YAML" do
    write_agent("noname.md", "---\ndescription: nothing\n---\n")
    write_agent("plain.md", "just text")
    write_agent("bad.md", "---\nname: [unclosed\n---\n")
    write_agent("ok.md", "---\nname: ok\n---\n")

    expect(described_class.new(directory).entries).to eq([ { name: "ok", description: "" } ])
  end

  it "truncates long descriptions and caps the number of entries" do
    write_agent("long.md", "---\nname: long\ndescription: #{'x' * 500}\n---\n")
    25.times { |i| write_agent("a#{i}.md", "---\nname: agent-#{format('%02d', i)}\n---\n") }

    entries = described_class.new(directory).entries

    expect(entries.size).to eq(20)
    expect(described_class.new(directory).entries.map { |e| e[:description].length }.max).to be <= 200
  end
end
