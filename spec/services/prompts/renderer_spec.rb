require "rails_helper"

RSpec.describe Prompts::Renderer do
  let_tmpdir(:local_directory, "renderer-spec")
  let(:project) do
    build_personal_project(
      local_directory: local_directory,
      jira_tester: "tess", uat_url: "https://uat.example", test_instructions: "run tests", uat_instructions: "check uat",
      local_url: "http://localhost:3000", local_instructions: "boot it", ci_instructions: "watch ci",
      ci_verify_instructions: "verify ci", pr_instructions: "open pr", ci_command: "bin/ci"
    )
  end
  let(:variables) { {} }
  let(:workflow) do
    build_task_workflow(
      project, kind: :development, task_description: "Do the thing", variables: variables,
      jira_ticket: "ABC-1", github_pr_url: "https://github.com/acme/app/pull/7", github_reviewer: "alice, bob",
      skills: "one, two", pr_skills: "pr-one", slack_url: "https://slack.example/t/1",
      ci_output_path: "/tmp/ci.log", ci_exit_status: 2, created_at: Time.utc(2026, 3, 4, 20, 0)
    )
  end

  after do
    workflow.destroy
    project.destroy
  end

  describe "BUILT_IN_TOKENS" do
    it "lists exactly the built-in tokens placeholders_for substitutes" do
      expect(described_class::BUILT_IN_TOKENS).to be_frozen
      expect(described_class::BUILT_IN_TOKENS).to match_array(described_class.placeholders_for(workflow).keys)
    end

    it "includes every project and workflow placeholder token" do
      expect(described_class::BUILT_IN_TOKENS).to include(*Prompts::ProjectPlaceholders::TOKENS)
      expect(described_class::BUILT_IN_TOKENS).to include(*Prompts::WorkflowPlaceholders::TOKENS)
    end

    it "keeps the cheatsheet order" do
      expect(described_class::BUILT_IN_TOKENS).to eq(
        %w[{JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK}] +
        %w[{TESTER} {UAT_URL} {TEST_INSTRUCTIONS} {UAT_INSTRUCTIONS} {LOCAL_URL} {LOCAL_INSTRUCTIONS}
           {CI_INSTRUCTIONS} {CI_VERIFY_INSTRUCTIONS} {PR_INSTRUCTIONS} {CI_COMMAND}] +
        %w[{CI_OUTPUT} {CI_STATUS} {STARTED_ON} {STAGE_NAME} {PREV_OUTPUT}]
      )
    end
  end

  describe ".render" do
    it "substitutes every built-in token" do
      allow(workflow).to receive(:image_paths).and_return(%w[/a.png /b.png])
      described_class.placeholders_for(workflow).each_key do |token|
        expect(described_class.render(token, workflow)).to eq(described_class.placeholders_for(workflow).fetch(token))
      end

      expect(described_class.render("{JIRA} {PR} {REVIEWER} {SKILLS} {PR_SKILLS} {IMAGES} {TASK} {SLACK}", workflow))
        .to eq("ABC-1 https://github.com/acme/app/pull/7 alice,bob one, two pr-one /a.png, /b.png Do the thing https://slack.example/t/1")
      expect(described_class.render("{TESTER} {UAT_URL} {CI_COMMAND} {CI_OUTPUT} {CI_STATUS}", workflow))
        .to eq("tess https://uat.example bin/ci /tmp/ci.log 2")
    end

    it "shows {STARTED_ON} in the Brisbane time zone" do
      expect(Prompts::WorkflowPlaceholders::STARTED_ON_TIME_ZONE).to eq("Australia/Brisbane")
      expect(described_class.render("{STARTED_ON}", workflow)).to eq("05/03/2026")
    end

    it "renders {STAGE_NAME} from the current stage" do
      workflow.stages.create!(stage_type: :implementation)
      expect(described_class.render("{STAGE_NAME}", workflow)).to eq(workflow.current_stage&.display_name.to_s)
    end

    it "leaves unknown tokens as-is" do
      expect(described_class.render("{NOPE} and {jira_lower}", workflow)).to eq("{NOPE} and {jira_lower}")
    end

    context "with custom variables" do
      let(:variables) { { "ENV" => "staging", "PR" => "hijack", "BLANK" => "" } }

      it "fills a token the built-ins do not define" do
        expect(described_class.render("{ENV}", workflow)).to eq("staging")
      end

      it "cannot override a built-in" do
        expect(described_class.render("{PR}", workflow)).to eq("https://github.com/acme/app/pull/7")
      end

      it "ignores empty variables" do
        expect(described_class.render("{BLANK}", workflow)).to eq("{BLANK}")
        expect(described_class.placeholders_for(workflow)).not_to have_key("{BLANK}")
      end
    end

    context "when a value contains another token" do
      let(:variables) { { "NOTE" => "see {JIRA}" } }

      it "does not re-expand it" do
        expect(described_class.render("{NOTE}", workflow)).to eq("see {JIRA}")
      end
    end

    describe "{PREV_OUTPUT}" do
      let(:runbook) { build_runbook_workflow(project) }
      let!(:first) { build_runbook_stage(runbook, name: "First") }
      let!(:second) { build_runbook_stage(runbook, name: "Second") }

      after { runbook.destroy }

      it "is the last PREV_OUTPUT_LIMIT chars of the previous stage's stage_completed output" do
        output = "x" * 10 + "y" * Prompts::WorkflowPlaceholders::PREV_OUTPUT_LIMIT
        first.log_run!("stage_completed", output: output)
        runbook.update!(current_stage_id: second.id)

        expect(described_class.render("{PREV_OUTPUT}", runbook)).to eq("y" * Prompts::WorkflowPlaceholders::PREV_OUTPUT_LIMIT)
      end

      it "is empty on the first stage" do
        runbook.update!(current_stage_id: first.id)
        expect(described_class.render("{PREV_OUTPUT}", runbook)).to eq("")
      end

      it "is empty when the previous stage has no stage_completed run" do
        first.log_run!("started")
        runbook.update!(current_stage_id: second.id)
        expect(described_class.render("{PREV_OUTPUT}", runbook)).to eq("")
      end

      it "is empty for non-runbook workflows" do
        expect(described_class.render("{PREV_OUTPUT}", workflow)).to eq("")
      end
    end
  end

  describe ".placeholders_for" do
    let(:variables) { { "ENV" => "staging" } }

    it "returns the keys and values render substitutes" do
      values = described_class.placeholders_for(workflow)

      expect(values).to include("{ENV}" => "staging", "{JIRA}" => "ABC-1")
      expect(values.keys).to include(*Prompts::ProjectPlaceholders.for(project).keys)
      values.each { |token, value| expect(described_class.render(token, workflow)).to eq(value) }
    end
  end
end
