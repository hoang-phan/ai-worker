require "rails_helper"

RSpec.describe Prompts::StagePrompt do
  subject(:stage_prompt) do
    described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log, section_list: section_list)
  end

  let(:notifier) { instance_double(Slack::ReviewNotifier, enabled?: false) }
  let(:latest_log) { ->(_workflow_id) { nil } }
  let(:section_list) { nil }

  let_tmpdir(:local_directory, "stage-prompt-spec")
  let(:project_attrs) { { kind: :personal } }
  let(:project) { build_personal_project(local_directory: local_directory, **project_attrs) }
  let(:workflow) do
    build_task_workflow(project, kind: :development, task_description: "Do the thing", variables: { "ENV" => "staging" })
  end
  let(:stage_type) { :task }
  let(:stage_attrs) { {} }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, **stage_attrs) }


  describe "#body" do
    context "when the stage has its own prompt" do
      let(:stage_attrs) { { prompt: "Own prompt: {TASK}", prompt_template: template } }
      let(:template) { PromptTemplate.create!(name: "tmpl #{SecureRandom.hex(4)}", stage_type: :task, body: "Template body") }


      it "wins over the template and renders placeholders" do
        expect(stage_prompt.body).to start_with("Own prompt: Do the thing")
      end
    end

    context "when the stage has a template" do
      let(:stage_attrs) { { prompt_template: template } }
      let(:template) { PromptTemplate.create!(name: "tmpl #{SecureRandom.hex(4)}", stage_type: :task, body: "Template: {TASK}") }


      it "uses and renders the template body" do
        expect(stage_prompt.body).to start_with("Template: Do the thing")
      end
    end

    {
      pr_review: Prompts::Defaults.for("pr_review"),
      jira_update: Prompts::Defaults.for("jira_update"),
      uat_test: Prompts::Defaults.for("uat_test"),
      local_test: Prompts::Defaults.for("local_test")
    }.each do |type, default_body|
      context "with a #{type} stage and no prompt or template" do
        let(:stage_type) { type }

        before { allow(stage).to receive(:effective_template).and_return(nil) }

        it "falls back to the rendered default body" do
          expect(stage_prompt.body).to eq(Prompts::Renderer.render(default_body, workflow))
        end
      end
    end

    context "with no prompt, template or default" do
      before { allow(stage).to receive(:effective_template).and_return(nil) }

      it "raises" do
        expect { stage_prompt.body }.to raise_error(ArgumentError, "no prompt available for stage #{stage.id}")
      end
    end

    it "appends sections in order after the rendered body" do
      stage.update!(prompt: "Do {TASK}")
      section_list = instance_double(Prompts::StageSectionList, to_s: " sections")
      prompt = described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log, section_list: section_list)

      expect(prompt.body).to eq("Do Do the thing sections")
    end

    it "uses the real section list when the injected list is nil" do
      stage.update!(prompt: "Do {TASK}")

      expect(stage_prompt.body).to include(
        "Do Do the thing",
        "If you discovered necessary work that is outside the scope of this task"
      )
    end
  end

  describe "#slack_message" do
    let(:stage_type) { :runbook_step }
    let(:stage_attrs) { { name: "Announce", run_mode: :message, channel: "#deploys-{ENV}" } }

    it "forwards to Prompts::SlackPost with the rendered channel" do
      expect(stage_prompt.slack_message("Hello")).to eq(
        Prompts::SlackPost.new(channel: "#deploys-staging", message: "Hello").to_s
      )
    end
  end
end
