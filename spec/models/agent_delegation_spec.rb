require "rails_helper"

RSpec.describe AgentDelegation do
  let(:local_directory) { Dir.mktmpdir("agent-delegation-spec") }
  let(:project) { build_jira_project(local_directory: local_directory) }
  let!(:billing) { project.agents.create!(name: "billing", description: "Knows billing") }
  let!(:invoicing) { project.agents.create!(name: "invoicing", description: "Knows invoices") }

  after do
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "links an agent to a delegate" do
    delegation = described_class.create!(agent: billing, delegate: invoicing)

    expect(delegation.agent).to eq(billing)
    expect(delegation.delegate).to eq(invoicing)
    expect(billing.reload.delegates).to eq([ invoicing ])
    expect(invoicing.delegating_links.map(&:agent)).to eq([ billing ])
  end

  it "requires an agent and a delegate" do
    expect(described_class.new(delegate: invoicing)).not_to be_valid
    expect(described_class.new(agent: billing)).not_to be_valid
  end

  it "allows a delegate only once per agent" do
    described_class.create!(agent: billing, delegate: invoicing)

    duplicate = described_class.new(agent: billing, delegate: invoicing)
    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:delegate_id]).to be_present
    expect(described_class.new(agent: invoicing, delegate: billing)).to be_valid
  end
end
