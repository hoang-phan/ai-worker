require "rails_helper"

RSpec.describe "Agents", type: :request do
  let_tmpdir(:local_directory, "agents-request-spec")
  let_tmpdir(:other_directory, "agents-request-spec-other")
  let(:project) { build_jira_project(local_directory: local_directory) }
  let(:other_project) { build_personal_project(local_directory: other_directory) }
  let!(:agent) { project.agents.create!(name: "billing", description: "Knows billing", effort: "high") }

  it "lists the agents on the project page" do
    get project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("billing", "Knows billing")
  end

  it "renders the new and edit forms" do
    get new_project_agent_path(project)
    expect(response).to have_http_status(:ok)

    get edit_project_agent_path(project, agent)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Knows billing")
  end

  describe "POST create" do
    it "creates an agent with delegates" do
      post project_agents_path(project), params: { agent: { name: "invoicing", description: "Knows invoices", model: "claude-sonnet-5-5", effort: "low", instructions: "See app/billing", delegate_ids: [ "", agent.id.to_s ] } }

      expect(response).to redirect_to(project_path(project))
      created = project.agents.find_by!(name: "invoicing")
      expect(created).to have_attributes(model: "claude-sonnet-5-5", effort: "low", instructions: "See app/billing")
      expect(created.delegates).to eq [ agent ]
    end

    it "ignores delegates from another project" do
      foreign = other_project.agents.create!(name: "foreign", description: "Elsewhere")

      post project_agents_path(project), params: { agent: { name: "invoicing", description: "Knows invoices", delegate_ids: [ foreign.id.to_s ] } }

      expect(project.agents.find_by!(name: "invoicing").delegates).to be_empty
    end

    it "re-renders the form on invalid input" do
      post project_agents_path(project), params: { agent: { name: "Bad Name", description: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(project.agents.count).to eq 1
    end
  end

  describe "PATCH update" do
    it "updates the agent" do
      patch project_agent_path(project, agent), params: { agent: { description: "New description", effort: "" } }

      expect(response).to redirect_to(project_path(project))
      expect(agent.reload).to have_attributes(description: "New description", effort: "")
    end

    it "does not reach an agent of another project" do
      foreign = other_project.agents.create!(name: "foreign", description: "Elsewhere")

      patch project_agent_path(project, foreign), params: { agent: { description: "Hijacked" } }

      expect(response).to have_http_status(:not_found)
      expect(foreign.reload.description).to eq "Elsewhere"
    end
  end

  describe "DELETE destroy" do
    it "deletes the agent" do
      delete project_agent_path(project, agent)

      expect(response).to redirect_to(project_path(project))
      expect(project.agents.count).to eq 0
    end
  end

  describe "provider and allowed tools" do
    it "saves the agent CLI and one tool per line" do
      post project_agents_path(project), params: { agent: { name: "invoicing", description: "Knows invoices", provider: "codex", allowed_tools_text: "Read\nGrep\n" } }

      expect(project.agents.find_by!(name: "invoicing")).to have_attributes(provider: "codex", allowed_tools: %w[Read Grep])
    end

    it "rejects an unknown agent CLI" do
      post project_agents_path(project), params: { agent: { name: "invoicing", description: "Knows invoices", provider: "gemini" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "offers the available CLIs on the form" do
      get new_project_agent_path(project)

      expect(Nokogiri::HTML(response.body).css("#agent_provider option").map(&:text)).to include("claude", "cursor", "codex")
    end
  end
end
