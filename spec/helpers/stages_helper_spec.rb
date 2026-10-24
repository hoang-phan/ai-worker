require "rails_helper"

RSpec.describe StagesHelper, type: :helper do
  describe "#stage_run_mode_options" do
    let(:expected) do
      {
        "agent" => "Run the prompt with the agent",
        "message" => "Post the text to Slack"
      }
    end

    it "has an explicit label for every Stage run mode" do
      expect(expected.keys).to match_array(Stage.run_modes.keys)
    end

    it "returns label and value pairs for each run mode" do
      expect(helper.stage_run_mode_options).to eq(expected.map { |run_mode, label| [ label, run_mode ] })
    end
  end

  describe "#stage_template_options" do
    let(:project) { build_jira_project }
    let(:workflow) { build_jira_workflow(project) }
    let(:stage) { workflow.stages.find_by!(stage_type: :implementation) }

    it "lists templates of the stage type by name with their bodies in data attributes" do
      later = PromptTemplate.create!(name: "Zebra", stage_type: :implementation, body: "Later body")
      first = PromptTemplate.create!(name: "Alpha", stage_type: :implementation, body: "First body")
      PromptTemplate.create!(name: "Other", stage_type: :task, body: "Other body")

      expect(helper.stage_template_options(stage)).to eq([
        [ first.name, first.id, { data: { body: first.body } } ],
        [ later.name, later.id, { data: { body: later.body } } ]
      ])
    end
  end

  describe "#stage_runnable?" do
    let(:project) { build_jira_project }
    let(:workflow) { build_runbook_workflow(project, status: :implementing) }
    let(:stage) { build_runbook_stage(workflow, name: "Build", position: 1) }
    let(:other_stage) { build_runbook_stage(workflow, name: "Ship", position: 2) }

    it "allows the current stage of an idle implementing runbook" do
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(true)
    end

    it "rejects another stage or a workflow that is processing" do
      expect(helper.stage_runnable?(workflow, other_stage, stage)).to be(false)

      workflow.update!(processing: true)
      expect(helper.stage_runnable?(workflow, stage, stage)).to be(false)
    end
  end

  describe "#current_stage_badge" do
    let(:stage) { Object.new }

    it "labels a waiting current stage" do
      workflow = instance_double(Workflow, waiting?: true)

      expect(helper.current_stage_badge(workflow, stage, stage)).to eq("waiting for Next")
    end

    it "labels a non-waiting current stage and leaves other stages blank" do
      workflow = instance_double(Workflow, waiting?: false)

      expect(helper.current_stage_badge(workflow, stage, stage)).to eq("current")
      expect(helper.current_stage_badge(workflow, Object.new, stage)).to be_nil
    end
  end

  describe "stage row helpers" do
    let_jira_project("stages-helper-spec")

    context "with a runbook workflow" do
      let(:workflow) { build_runbook_workflow(project) }
      let(:stage) do
        build_runbook_stage(workflow, name: "Deploy", run_mode: :message, channel: "#deploys", auto_advance: true,
                                      wait_for_workflow: "deploy.yml")
      end

      it "uses Stage / Channel headers" do
        expect(helper.stage_table_headers(workflow)).to eq([ "Stage", "Channel" ])
      end

      it "names the row by display name and details it by channel" do
        expect(helper.stage_row_name(workflow, stage)).to eq("Deploy")
        expect(helper.stage_row_detail(workflow, stage)).to eq("#deploys")
      end

      it "badges run mode, the awaited workflow and auto advance" do
        expect(helper.stage_row_badges(workflow, stage)).to eq(
          '<span class="badge badge-neutral">message</span> ' \
          '<span class="badge badge-neutral">waits for deploy.yml</span> ' \
          '<span class="badge badge-neutral">→ auto</span>'
        )
      end

      it "omits the waits-for badge and pauses for Next without auto advance" do
        stage.update!(run_mode: :agent, channel: nil, auto_advance: false, wait_for_workflow: nil)

        expect(helper.stage_row_badges(workflow, stage)).to eq(
          '<span class="badge badge-neutral">agent</span> <span class="badge badge-neutral">⏸ then Next</span>'
        )
      end
    end

    context "with a development workflow" do
      let(:workflow) { build_jira_workflow(project) }
      let(:stage) { workflow.stages.find_by!(stage_type: :implementation) }

      it "uses Type / Template headers" do
        expect(helper.stage_table_headers(workflow)).to eq([ "Type", "Template" ])
      end

      it "names the row by stage type and details it by the effective template" do
        template = PromptTemplate.create!(name: "Impl default", stage_type: :implementation, body: "Body")

        expect(helper.stage_row_name(workflow, stage)).to eq("implementation")
        expect(helper.stage_row_detail(workflow, stage)).to eq(template.name)
      end

      it "has no badges without an awaited workflow" do
        expect(helper.stage_row_badges(workflow, stage)).to be_blank
      end

      it "badges only the awaited workflow" do
        stage.update!(wait_for_workflow: "deploy.yml")

        expect(helper.stage_row_badges(workflow, stage)).to eq('<span class="badge badge-neutral">waits for deploy.yml</span>')
      end
    end
  end
end
