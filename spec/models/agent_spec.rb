require "rails_helper"

RSpec.describe Agent do
  let(:local_directory) { Dir.mktmpdir("agent-spec") }
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:other_project) { Project.create!(name: "Other agent project", kind: :personal, local_directory: Dir.mktmpdir("agent-spec-other")) }

  after do
    [ local_directory, other_project.local_directory ].each do |dir|
      FileUtils.remove_entry(dir) if dir.start_with?(Dir.tmpdir) && File.exist?(dir)
    end
  end

  def build_agent(**attributes)
    project.agents.new({ name: "billing", description: "Knows billing" }.merge(attributes))
  end

  it "requires a slug name and a description" do
    agent = project.agents.new
    expect(agent).not_to be_valid
    expect(agent.errors[:name]).to be_present
    expect(agent.errors[:description]).to be_present

    [ "Billing Expert", "billing_expert", "-billing", "billing-" ].each do |name|
      expect(build_agent(name: name)).not_to be_valid
    end
    expect(build_agent(name: "billing-v2")).to be_valid
  end

  it "keeps names unique per project only" do
    build_agent.save!

    expect(build_agent).not_to be_valid
    expect(other_project.agents.new(name: "billing", description: "Knows billing")).to be_valid
  end

  describe "model and effort" do
    it "allows blank values" do
      expect(build_agent(model: "", effort: "")).to be_valid
    end

    it "accepts known efforts and model ids" do
      Agent::EFFORTS.each do |effort|
        expect(build_agent(effort: effort, model: "claude-opus-5-5[1m]")).to be_valid
      end
    end

    it "rejects an unknown effort" do
      agent = build_agent(effort: "extreme")
      expect(agent).not_to be_valid
      expect(agent.errors[:effort]).to be_present
    end

    it "rejects a model with spaces or shell characters" do
      [ "claude sonnet", "x;rm -rf" ].each do |model|
        expect(build_agent(model: model)).not_to be_valid
      end
    end
  end

  describe "delegates" do
    let!(:billing) { build_agent.tap(&:save!) }
    let!(:invoicing) { project.agents.create!(name: "invoicing", description: "Knows invoices") }

    it "links to other agents of the same project" do
      billing.update!(delegates: [ invoicing ])

      expect(billing.reload.delegates).to eq [ invoicing ]
    end

    it "rejects the agent itself" do
      billing.delegates = [ billing ]

      expect(billing).not_to be_valid
      expect(billing.errors[:delegates]).to include("cannot include the agent itself")
    end

    it "rejects an agent from another project" do
      foreign = other_project.agents.create!(name: "foreign", description: "Elsewhere")
      billing.delegates = [ foreign ]

      expect(billing).not_to be_valid
      expect(billing.errors[:delegates]).to include("must belong to the same project")
    end

    it "removes links in both directions when an agent is destroyed" do
      billing.update!(delegates: [ invoicing ])

      expect { invoicing.destroy! }.to change(AgentDelegation, :count).by(-1)
      expect(billing.reload.delegates).to be_empty
    end
  end

  it "is unset on its stages when destroyed" do
    workflow = build_jira_workflow(project, jira_ticket: "AG-1", branch_name: "ag-1", status: :implementing)
    stage = workflow.stages.create!(stage_type: :implementation, name: "implementation")
    agent = build_agent.tap(&:save!)
    stage.update!(agent: agent)

    agent.destroy!

    expect(stage.reload.agent).to be_nil
  end
end
