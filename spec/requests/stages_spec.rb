require "rails_helper"

RSpec.describe "Stages", type: :request do
  let(:local_directory) { Dir.mktmpdir("stages-request-spec") }
  let(:project) { Project.create!(name: "Stages spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }
  let(:development_workflow) do
    project.workflows.create!(jira_ticket: "STG-1", branch_name: "stages-spec", github_reviewer: "someone")
  end
  let(:runbook) { project.workflows.create!(kind: :runbook) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "runbook-only stage lists" do
    it "redirects new, create, and destroy on a non-runbook workflow" do
      stage = development_workflow.stages.first

      get new_project_workflow_stage_path(project, development_workflow)
      expect(response).to redirect_to(project_workflow_path(project, development_workflow))
      expect(flash[:alert]).to eq("Only runbook workflows have editable stage lists.")

      expect do
        post project_workflow_stages_path(project, development_workflow), params: { stage: { name: "Ignored" } }
      end.not_to change(development_workflow.stages, :count)
      expect(response).to redirect_to(project_workflow_path(project, development_workflow))
      expect(flash[:alert]).to eq("Only runbook workflows have editable stage lists.")

      expect do
        delete project_workflow_stage_path(project, development_workflow, stage)
      end.not_to change(Stage, :count)
      expect(response).to redirect_to(project_workflow_path(project, development_workflow))
      expect(flash[:alert]).to eq("Only runbook workflows have editable stage lists.")
    end
  end

  describe "stage prompt form" do
    def expect_prompt_form(template)
      document = Nokogiri::HTML(response.body)

      expect(document.at_css('[data-controller~="skill-insert"][data-controller~="template-fill"]')).to be_present
      expect(document.at_css('[data-template-fill-placeholders-value]')).to be_present
      expect(document.at_css('#stage_prompt_template_id[data-template-fill-target="select"][data-action="change->template-fill#fill"]')).to be_present
      expect(document.at_css("#stage_prompt_template_id option[data-body='#{template.body}']")).to be_present
      expect(document.at_css('#stage_prompt[data-skill-insert-target="input"][data-template-fill-target="input"]')).to be_present
      expect(document.css("body script")).to be_empty
    end

    it "uses Stimulus controllers on the new stage page" do
      template = PromptTemplate.create!(name: "Deploy prompt", stage_type: :runbook_step, body: "Deploy {STAGE_NAME}")

      get new_project_workflow_stage_path(project, runbook)

      expect(response).to have_http_status(:ok)
      expect_prompt_form(template)
    end

    it "uses Stimulus controllers on the edit stage page" do
      stage = development_workflow.stages.find_by!(stage_type: :implementation)
      template = PromptTemplate.create!(name: "Implement prompt", stage_type: :implementation, body: "Implement {JIRA}")

      get edit_project_workflow_stage_path(project, development_workflow, stage)

      expect(response).to have_http_status(:ok)
      expect_prompt_form(template)
    end
  end

  describe "POST create" do
    it "adds a runbook step even when another stage type is posted" do
      expect do
        post project_workflow_stages_path(project, runbook), params: {
          stage: { name: "Deploy", position: 1, stage_type: "implementation", prompt: "Ship it" }
        }
      end.to change(runbook.stages, :count).by(1)

      stage = runbook.stages.last
      expect(response).to redirect_to(project_workflow_path(project, runbook))
      expect(flash[:notice]).to eq("Stage added.")
      expect(stage).to be_runbook_step
      expect(stage.name).to eq("Deploy")
    end

    it "re-renders new with validation errors" do
      expect do
        post project_workflow_stages_path(project, runbook), params: {
          stage: { name: "Notify", position: 1, run_mode: "message", channel: "" }
        }
      end.not_to change(Stage, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("error prevented this stage from saving")
    end
  end

  describe "PATCH update" do
    it "only permits prompt fields on a non-runbook workflow" do
      stage = development_workflow.stages.find_by!(stage_type: :implementation)

      patch project_workflow_stage_path(project, development_workflow, stage), params: {
        stage: { prompt_template_id: nil, prompt: "Updated prompt", name: "Ignored", run_mode: "message" }
      }

      expect(response).to redirect_to(project_workflow_path(project, development_workflow))
      expect(stage.reload).to have_attributes(prompt: "Updated prompt", name: nil, run_mode: "agent")
    end
  end

  describe "DELETE destroy" do
    let!(:current_stage) { runbook.stages.create!(stage_type: :runbook_step, name: "Current", position: 1) }

    it "refuses the current stage of a started runbook" do
      runbook.update!(status: :implementing, current_stage_id: current_stage.id)

      expect do
        delete project_workflow_stage_path(project, runbook, current_stage)
      end.not_to change(Stage, :count)

      expect(response).to redirect_to(project_workflow_path(project, runbook))
      expect(flash[:alert]).to eq("That is the current stage; move on first.")
    end

    it "allows removal while pending or when the stage is not current" do
      runbook.update!(current_stage_id: current_stage.id)

      expect do
        delete project_workflow_stage_path(project, runbook, current_stage)
      end.to change(Stage, :count).by(-1)

      other_stage = runbook.stages.create!(stage_type: :runbook_step, name: "Other", position: 2)
      runbook.update!(status: :implementing, current_stage_id: other_stage.id)

      expect do
        delete project_workflow_stage_path(project, runbook, other_stage)
      end.not_to change(Stage, :count)

      non_current_stage = runbook.stages.create!(stage_type: :runbook_step, name: "Non-current", position: 3)
      expect do
        delete project_workflow_stage_path(project, runbook, non_current_stage)
      end.to change(Stage, :count).by(-1)
    end
  end
end
