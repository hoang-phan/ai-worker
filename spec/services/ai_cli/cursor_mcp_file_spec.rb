require "rails_helper"
require "tmpdir"

RSpec.describe AiCli::CursorMcpFile do
  let(:servers) { { "browser" => { "command" => "npx", "args" => [ "browser-mcp" ] } } }
  let(:cmd) { [ "agent", "-p", "do it" ] }

  around do |example|
    Dir.mktmpdir do |dir|
      @project = File.join(dir, "project")
      FileUtils.mkdir_p(@project)
      @mcp_config = File.join(dir, "mcp-config.json")
      File.write(@mcp_config, JSON.generate(mcpServers: servers))
      example.run
    end
  end

  let(:mcp_file) { File.join(@project, ".cursor", "mcp.json") }
  let(:backup) { "#{mcp_file}.ai-worker-bak" }
  let(:exclude) { File.join(@project, ".git", "info", "exclude") }

  def wrap
    described_class.new(@project, @mcp_config).wrap(cmd)
  end

  it "writes mcp.json with the servers from the mcp config" do
    wrap
    expect(JSON.parse(File.read(mcp_file))).to eq("mcpServers" => servers)
  end

  it "moves an existing mcp.json to the backup" do
    FileUtils.mkdir_p(File.dirname(mcp_file))
    File.write(mcp_file, "original")
    wrap
    expect(File.read(backup)).to eq("original")
    expect(JSON.parse(File.read(mcp_file))).to eq("mcpServers" => servers)
  end

  it "does not overwrite an existing backup" do
    FileUtils.mkdir_p(File.dirname(mcp_file))
    File.write(backup, "first")
    File.write(mcp_file, "leftover")
    wrap
    expect(File.read(backup)).to eq("first")
  end

  it "appends the exclude lines once when .git/info exists" do
    FileUtils.mkdir_p(File.dirname(exclude))
    File.write(exclude, "tmp")
    wrap
    wrap
    expect(File.read(exclude)).to eq("tmp\n.cursor/mcp.json\n.cursor/mcp.json.ai-worker-bak\n")
  end

  it "does not create .git/info when it is missing" do
    wrap
    expect(File.exist?(File.join(@project, ".git"))).to be(false)
  end

  it "returns an sh -c wrapper ending with the original command" do
    argv = wrap
    expect(argv.first(2)).to eq([ "sh", "-c" ])
    expect(argv).to include(mcp_file)
    expect(argv.last(cmd.size)).to eq(cmd)
  end
end
