require "rails_helper"

RSpec.describe Prompts::StagePrompt do
  subject(:stage_prompt) do
    described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log, subagent_roster: subagent_roster,
                        run_provider: run_provider)
  end

  let(:notifier) { instance_double(Slack::ReviewNotifier, enabled?: false) }
  let(:latest_log) { ->(_workflow_id) { nil } }
  let(:subagent_roster) { ->(_directory) { [] } }
  let(:run_provider) { instance_double(Stages::RunProvider, provider: nil) }

  let_tmpdir(:local_directory, "stage-prompt-spec")
  let(:project_attrs) { { kind: :personal } }
  let(:project) { build_personal_project(local_directory: local_directory, **project_attrs) }
  let(:workflow) do
    build_task_workflow(project, kind: :development, task_description: "Do the thing", variables: { "ENV" => "staging" })
  end
  let(:stage_type) { :task }
  let(:stage_attrs) { {} }
  let(:stage) { workflow.stages.create!(stage_type: stage_type, **stage_attrs) }

  after do
    stage.destroy
    workflow.destroy
    project.destroy
  end

  describe "#body" do
    context "when the stage has its own prompt" do
      let(:stage_attrs) { { prompt: "Own prompt: {TASK}", prompt_template: template } }
      let(:template) { PromptTemplate.create!(name: "tmpl #{SecureRandom.hex(4)}", stage_type: :task, body: "Template body") }

      after { template.destroy }

      it "wins over the template and renders placeholders" do
        expect(stage_prompt.body).to start_with("Own prompt: Do the thing")
      end
    end

    context "when the stage has a template" do
      let(:stage_attrs) { { prompt_template: template } }
      let(:template) { PromptTemplate.create!(name: "tmpl #{SecureRandom.hex(4)}", stage_type: :task, body: "Template: {TASK}") }

      after { template.destroy }

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

    it "passes retry a log only for a failed implementation run from this workflow" do
      stage.update!(stage_type: :implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "failed")
      previous_log = "/tmp/runs/workflow-#{workflow.id}.log"
      latest_log = instance_double(Proc)
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).to receive(:call).with(workflow.id).and_return(previous_log)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "implementation", last_action: "failed", previous_log: previous_log
      ).and_return(retry_section)

      described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log,
                          subagent_roster: subagent_roster, run_provider: run_provider).body
    end

    it "does not look up a retry log unless a simple implementation's last action failed" do
      stage.update!(stage_type: :simple_implementation, prompt: "Implement")
      stage.stage_runs.create!(action: "started")
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).not_to receive(:call)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "simple_implementation", last_action: "started", previous_log: nil
      ).and_return(retry_section)

      stage_prompt.body
    end

    it "does not look up a retry log for failed non-implementation stages" do
      stage.update!(prompt: "Do it")
      stage.stage_runs.create!(action: "failed")
      retry_section = instance_double(Prompts::StageSections::Retry, to_s: "")

      expect(latest_log).not_to receive(:call)
      expect(Prompts::StageSections::Retry).to receive(:new).with(
        stage_type: "task", last_action: "failed", previous_log: nil
      ).and_return(retry_section)

      stage_prompt.body
    end

    it "passes local-test readiness and this workflow's feedback to local feedback" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      allow(project).to receive(:local_test_ready?).and_return(true)
      allow(workflow).to receive(:local_test_feedback).and_return("Login button is broken")
      local_feedback = instance_double(Prompts::StageSections::LocalFeedback, to_s: "")

      expect(Prompts::StageSections::LocalFeedback).to receive(:new).with(
        stage_type: "pr_check", local_test_ready: true, feedback: "Login button is broken"
      ).and_return(local_feedback)

      stage_prompt.body
    end

    it "does not mark a non-pr-check stage as local-test ready" do
      stage.update!(prompt: "Do it")
      allow(project).to receive(:local_test_ready?).and_return(true)
      local_feedback = instance_double(Prompts::StageSections::LocalFeedback, to_s: "")

      expect(Prompts::StageSections::LocalFeedback).to receive(:new).with(
        stage_type: "task", local_test_ready: false, feedback: workflow.local_test_feedback
      ).and_return(local_feedback)

      stage_prompt.body
    end

    it "only enables fixed summaries for pr checks when the notifier is enabled" do
      stage.update!(stage_type: :pr_check, prompt: "Fix")
      allow(notifier).to receive(:enabled?).and_return(true)
      fixed_summary = instance_double(Prompts::StageSections::FixedSummary, to_s: "")

      expect(Prompts::StageSections::FixedSummary).to receive(:new).with(
        stage_type: "pr_check", notify_enabled: true
      ).and_return(fixed_summary)

      stage_prompt.body
    end

    it "does not enable fixed summaries outside pr checks" do
      stage.update!(prompt: "Do it")
      allow(notifier).to receive(:enabled?).and_return(true)
      fixed_summary = instance_double(Prompts::StageSections::FixedSummary, to_s: "")

      expect(Prompts::StageSections::FixedSummary).to receive(:new).with(
        stage_type: "task", notify_enabled: false
      ).and_return(fixed_summary)

      stage_prompt.body
    end

    it "passes project lessons to the lessons section" do
      stage.update!(prompt: "Do it")
      project.update!(agent_lessons: "Use the shared error_summary partial on forms")
      lessons = instance_double(Prompts::StageSections::Lessons, to_s: "")

      expect(Prompts::StageSections::Lessons).to receive(:new).with(
        stage_type: "task", lessons: "Use the shared error_summary partial on forms"
      ).and_return(lessons)

      stage_prompt.body
    end

    it "gets the subagent roster from the project's local directory" do
      stage.update!(prompt: "Do it")
      entries = [ { name: "reviewer", description: "Reviews diffs" } ]
      subagents = instance_double(Prompts::StageSections::Subagents, to_s: "")

      expect(Prompts::StageSections::Subagents).to receive(:new).with(stage_type: "task", entries: entries).and_return(subagents)

      described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log,
                          subagent_roster: ->(directory) { directory == local_directory ? entries : [] },
                          run_provider: run_provider).body
    end

    it "appends sections in order after the rendered body" do
      stage.update!(prompt: "Do {TASK}")
      section_classes = [
        Prompts::StageSections::Retry, Prompts::StageSections::LocalFeedback,
        Prompts::StageSections::FixedSummary, Prompts::StageSections::LessonsRequest,
        Prompts::StageSections::FollowUps, Prompts::StageSections::Lessons,
        Prompts::StageSections::CheckOutput, Prompts::StageSections::Subagents
      ]
      outputs = section_classes.each_with_index.map do |klass, index|
        output = " section-#{index}"
        allow(klass).to receive(:new).and_return(instance_double(klass, to_s: output))
        output
      end

      expect(stage_prompt.body).to eq("Do Do the thing#{outputs.join}")
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

  describe "CONFLICT" do
    it "aliases Prompts::ConflictResolution::TEXT" do
      expect(described_class::CONFLICT).to equal(Prompts::ConflictResolution::TEXT)
    end
  end

  describe "agent brief" do
    let(:stage_attrs) { { prompt: "Do {TASK}" } }

    it "does not build an agent brief without a stage agent" do
      project.agents.create!(name: "billing", description: "Billing", instructions: "Project-wide notes")
      expect(Prompts::StageSections::AgentBrief).not_to receive(:new)

      stage_prompt.body
    end

    it "prepends the stage agent's brief" do
      agent = project.agents.create!(name: "billing", description: "Knows billing", instructions: "Invoices live in app/billing.")
      stage.update!(agent: agent)
      brief = instance_double(Prompts::StageSections::AgentBrief, to_s: "BRIEF")

      expect(Prompts::StageSections::AgentBrief).to receive(:new).with(
        name: "billing", description: "Knows billing", instructions: "Invoices live in app/billing.",
        allowed_tools: [], tools_enforced: nil
      ).and_return(brief)
      expect(stage_prompt.body).to start_with("BRIEFDo Do the thing")
    end

    it "uses the run provider's tool-list capability for the agent brief" do
      agent = project.agents.create!(name: "billing", description: "Billing", provider: "codex", allowed_tools: [ "Read" ])
      stage.update!(agent: agent)
      provider = instance_double(AiCli::Provider, capabilities: AiCli::Provider::Capabilities.new(tool_lists: false, model: true, effort: true, mcp: :overrides))
      run_provider = instance_double(Stages::RunProvider, provider: provider)
      brief = instance_double(Prompts::StageSections::AgentBrief, to_s: "")

      expect(Prompts::StageSections::AgentBrief).to receive(:new).with(
        name: "billing", description: "Billing", instructions: "", allowed_tools: [ "Read" ], tools_enforced: false
      ).and_return(brief)

      described_class.new(workflow, stage, notifier: notifier, latest_log: latest_log,
                          subagent_roster: subagent_roster, run_provider: run_provider).body
    end
  end
end
