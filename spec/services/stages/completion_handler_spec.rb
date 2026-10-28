require "rails_helper"

RSpec.describe Stages::CompletionHandler, type: :service do
  let(:project) { build_jira_project }
  let(:workflow) do
    build_jira_workflow(project, jira_ticket: "DONE-1", branch_name: "completion-handler", github_pr_url: "https://github.com/acme/widgets/pull/1", status: :implementing, **running_ai_run)
  end
  let(:stage_type) { :implementation }
  let(:stage) { build_stage(workflow, stage_type) }
  let(:github) { instance_double(Github::Client) }
  let(:git) { class_double(Git::BranchService) }
  let(:handoff) { instance_double(Stages::ReviewHandoff) }
  let(:output) { "agent output" }

  def handle(out = output, finishers: described_class::FINISHERS)
    described_class.new(
      workflow: workflow,
      stage: stage,
      project: project,
      github: github,
      git: git,
      handoff: handoff,
      finishers: finishers
    ).call(out)
  end

  describe "dispatch over Stage::STAGE_TYPES" do
    finishers = {
      "implementation" => [ Stages::ImplementationFinish, %i[workflow stage project github handoff] ],
      "pr_check" => [ Stages::PrCheckFinish, %i[workflow stage project github handoff] ],
      "task" => [ Stages::TaskFinish, %i[workflow stage project git] ],
      "pr_review" => [ Stages::PrReviewFinish, %i[workflow stage] ],
      "jira_update" => [ Stages::JiraUpdateFinish, %i[workflow stage project] ],
      "uat_test" => [ Stages::UatTestFinish, %i[workflow stage] ],
      "local_test" => [ Stages::LocalTestFinish, %i[workflow stage handoff] ],
      "ci_check" => [ Stages::CiCheckFinish, %i[workflow stage] ],
      "simple_implementation" => [ Stages::SimpleImplementationFinish, %i[workflow stage] ],
      "ci_verify" => [ Stages::CiVerifyFinish, %i[workflow stage project handoff] ],
      "pr_create" => [ Stages::PrCreateFinish, %i[workflow stage project github handoff] ],
      "runbook_step" => [ Stages::RunbookStepFinish, %i[workflow stage] ]
    }
    types_without_finishers = [].freeze

    it "covers every stage type" do
      expect(described_class::FINISHERS.keys).to match_array(Stage::STAGE_TYPES.keys.map(&:to_s) - types_without_finishers)
      expect(described_class::FINISHERS).to eq(finishers)

      fake_finisher = Class.new do
        attr_reader :kwargs

        def initialize(**kwargs)
          @kwargs = kwargs
        end

        def call(_output)
          self
        end
      end

      result = handle(finishers: { "implementation" => [ fake_finisher, %i[workflow stage handoff] ] })

      expect(result.kwargs).to eq(workflow: workflow, stage: stage, handoff: handoff)
    end

    Stage::STAGE_TYPES.each_key do |type|
      context "with #{type}" do
        let(:stage_type) { type }

        it "dispatches to an injected finisher" do
          klass, = finishers.fetch(type.to_s)
          finisher = instance_double(klass, call: nil)
          received = nil
          injected_finishers = {
            type.to_s => ->(**kwargs) { received = kwargs; finisher }
          }
          handle(finishers: injected_finishers)

          expect(received).to eq(workflow: workflow, stage: stage, project: project, github: github, git: git, handoff: handoff)
          expect(finisher).to have_received(:call).with(output)
        end
      end
    end
  end

  it "propagates a missing JIRA_RESULT error from the finisher" do
    stage.update!(stage_type: :jira_update)

    expect { handle }.to raise_error(AiCli::CommandError, /JIRA_RESULT/)
  end

  it "is a no-op returning nil for an unknown stage type" do
    # Enum rejects unknown values; stub to exercise the dispatch guard.
    allow(stage).to receive(:stage_type).and_return("bogus")
    expect(handle).to be_nil
  end
end
