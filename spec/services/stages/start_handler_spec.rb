require "rails_helper"

RSpec.describe Stages::StartHandler, type: :service do
  let_jira_project("start-handler-spec")
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "START-1", branch_name: "start-handler", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing)
  end
  let(:stage_type) { :implementation }
  let(:stage) { build_stage(workflow, stage_type) }
  let(:github) { double("Github::Client") }
  let(:git) { class_double(Git::BranchService, create_branch!: nil, checkout_remote_branch!: nil, update_with_main!: :updated) }
  let(:prompt) { instance_double(Prompts::StagePrompt, body: "the prompt") }
  let(:handoff) { double("Stages::ReviewHandoff", reviewers: [ "octocat" ]) }
  let(:launcher) { spy("Stages::AiRunLauncher") }

  let(:starter_names) { %i[pr_check pr_review ci_check browser_test runbook_step] }
  let(:built) { Hash.new { |hash, name| hash[name] = [] } }
  let(:fake_starters) do
    starter_names.to_h do |name|
      [ name, lambda { |**args|
        built[name] << args
        double("#{name} starter", call: name)
      } ]
    end
  end

  def handler
    described_class.new(workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt,
                        handoff: handoff, launcher: launcher, starters: fake_starters)
  end

  def expect_run_started(prompt_text = "the prompt", **options)
    expect(launcher).to have_received(:call).with(prompt_text, **options)
  end

  describe "implementation" do
    it "creates the branch and starts the agent" do
      handler.call

      expect(git).to have_received(:create_branch!).with(project, "start-handler")
      expect_run_started
    end

    it "propagates a branch error without starting the agent" do
      allow(git).to receive(:create_branch!).and_raise(Git::CommandError, "nope")

      expect { handler.call }.to raise_error(Git::CommandError, "nope")
      expect(launcher).not_to have_received(:call)
    end
  end

  describe "prompt-only stages" do
    Stages::StartHandler::PROMPT_ONLY_TYPES.each do |type|
      context type do
        let(:stage_type) { type }

        it "starts the agent with the rendered prompt and does not create a branch" do
          handler.call

          expect(git).not_to have_received(:create_branch!)
          expect_run_started
        end
      end
    end
  end

  describe "dispatch over Stage::STAGE_TYPES" do
    Stage::STAGE_TYPES.each_key do |type|
      context "with #{type}" do
        let(:stage_type) { type }

        it "dispatches exactly one start path" do
          started_paths = []
          allow(launcher).to receive(:call) { started_paths << :launcher }
          starter_names.each do |name|
            fake_starters[name] = lambda { |**|
              starter = double("#{name} starter")
              allow(starter).to receive(:call) { started_paths << name }
              starter
            }
          end

          handler.call

          expect(started_paths.size).to eq(1),
            "expected stage type #{type.inspect} to dispatch exactly one start path, but dispatched #{started_paths.inspect}"
        end
      end
    end
  end

  describe "simple_implementation" do
    let(:stage_type) { :simple_implementation }

    it "creates the branch and starts the agent" do
      handler.call

      expect(git).to have_received(:create_branch!).with(project, "start-handler")
      expect_run_started
    end
  end

  describe "ci_check" do
    let(:stage_type) { :ci_check }

    it "delegates to Stages::CiCheckStart" do
      handler.call

      expect(built[:ci_check]).to contain_exactly(hash_including(stage: stage, project: project, launcher: launcher))
      expect(built.keys).to eq([ :ci_check ])
    end
  end

  describe "pr_review" do
    let(:stage_type) { :pr_review }

    it "delegates to Stages::PrReviewStart" do
      handler.call

      expect(built[:pr_review]).to contain_exactly(
        hash_including(workflow: workflow, stage: stage, project: project, github: github, git: git, prompt: prompt, launcher: launcher)
      )
      expect(built.keys).to eq([ :pr_review ])
    end
  end

  describe "browser-test stages" do
    Stages::StartHandler::BROWSER_TEST_KINDS.each do |type, kind|
      context type do
        let(:stage_type) { type }

        it "delegates to BrowserTestStart for the #{kind} kind" do
          handler.call

          expect(built[:browser_test]).to contain_exactly(
            hash_including(workflow: workflow, project: project, kind: kind, prompt: prompt, git: git, launcher: launcher)
          )
          expect(built.keys).to eq([ :browser_test ])
        end
      end
    end
  end

  describe "runbook_step" do
    let(:stage_type) { :runbook_step }

    it "delegates to Stages::RunbookStepStart" do
      handler.call

      expect(built[:runbook_step]).to contain_exactly(
        hash_including(workflow: workflow, stage: stage, github: github, prompt: prompt, launcher: launcher)
      )
      expect(built.keys).to eq([ :runbook_step ])
    end
  end

  describe "pr_check" do
    let(:stage_type) { :pr_check }

    it "delegates to Stages::PrCheckRun, passing the launcher" do
      handler.call

      expect(built[:pr_check]).to contain_exactly(
        hash_including(workflow: workflow, stage: stage, project: project, github: github, git: git,
                       handoff: handoff, prompt: prompt, launcher: launcher)
      )
      expect(built.keys).to eq([ :pr_check ])
    end
  end

  it "is a no-op returning nil for an unknown stage type" do
    allow(stage).to receive(:stage_type).and_return("bogus")

    expect(handler.call).to be_nil
    expect(launcher).not_to have_received(:call)
    expect(built).to be_empty
  end

  describe "default STARTERS" do
    it "builds each start service with the right class and collaborators" do
      args = { workflow: workflow, stage: stage, project: project, github: github, git: git,
               prompt: prompt, handoff: handoff, launcher: launcher }
      expectations = {
        pr_check: [ Stages::PrCheckRun, args ],
        pr_review: [ Stages::PrReviewStart, args.except(:handoff) ],
        ci_check: [ Stages::CiCheckStart, args.slice(:stage, :project, :launcher) ],
        browser_test: [ Stages::BrowserTestStart, args.slice(:workflow, :project, :prompt, :git, :launcher).merge(kind: :uat) ],
        runbook_step: [ Stages::RunbookStepStart, args.slice(:workflow, :stage, :github, :prompt, :launcher) ]
      }
      expect(described_class::STARTERS.keys).to match_array(expectations.keys)

      expectations.each do |name, (klass, expected)|
        instance = instance_double(klass)
        allow(klass).to receive(:new).and_return(instance)

        built_instance = described_class::STARTERS.fetch(name).call(**args, kind: :uat)

        expect(klass).to have_received(:new).with(expected)
        expect(built_instance).to eq(instance)
      end
    end
  end
end
