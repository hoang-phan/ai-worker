require "rails_helper"

RSpec.describe Prompts::WorkflowPlaceholders do
  let(:local_directory) { Dir.mktmpdir("workflow-placeholders-spec") }
  let(:project) do
    Project.create!(name: "WorkflowPlaceholders spec #{SecureRandom.hex(4)}", local_directory: local_directory, kind: :personal)
  end
  let(:workflow) do
    Workflow.create!(
      project: project, kind: :development, task_description: "Do the thing",
      jira_ticket: "ABC-1", github_pr_url: "https://github.com/acme/app/pull/7", github_reviewer: "alice, bob",
      skills: "one, two", pr_skills: "pr-one", slack_url: "https://slack.example/t/1",
      ci_output_path: "/tmp/ci.log", ci_exit_status: 2, created_at: Time.utc(2026, 3, 4, 20, 0)
    )
  end

  after do
    workflow.destroy
    project.destroy
    FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory)
  end

  it "lists every token it substitutes in TOKENS" do
    expect(described_class::TOKENS).to be_frozen
    expect(described_class::TOKENS).to match_array(described_class.for(workflow).keys)
  end

  it "maps each workflow field to its token" do
    allow(workflow).to receive(:image_paths).and_return(%w[/a.png /b.png])
    workflow.stages.create!(stage_type: :implementation)

    expect(described_class.for(workflow)).to eq(
      "{JIRA}" => "ABC-1",
      "{PR}" => "https://github.com/acme/app/pull/7",
      "{REVIEWER}" => "alice,bob",
      "{SKILLS}" => "one, two",
      "{PR_SKILLS}" => "pr-one",
      "{IMAGES}" => "/a.png, /b.png",
      "{TASK}" => "Do the thing",
      "{SLACK}" => "https://slack.example/t/1",
      "{CI_OUTPUT}" => "/tmp/ci.log",
      "{CI_STATUS}" => "2",
      "{STARTED_ON}" => "05/03/2026",
      "{STAGE_NAME}" => workflow.current_stage&.display_name.to_s,
      "{PREV_OUTPUT}" => ""
    )
  end

  it "has an empty {STAGE_NAME} without a current stage" do
    expect(described_class.for(workflow)["{STAGE_NAME}"]).to eq("")
  end

  describe "{STARTED_ON}" do
    it "is dd/mm/yyyy in the Brisbane time zone" do
      expect(described_class::STARTED_ON_TIME_ZONE).to eq("Australia/Brisbane")
      # 20:00 UTC on the 4th is already the 5th in Brisbane (UTC+10).
      expect(described_class.for(workflow)["{STARTED_ON}"]).to eq("05/03/2026")
    end
  end

  describe "{PREV_OUTPUT}" do
    let(:runbook) { Workflow.create!(project: project, kind: :runbook, task_description: "rb") }
    let!(:first) { runbook.stages.create!(stage_type: :runbook_step, name: "First") }
    let!(:second) { runbook.stages.create!(stage_type: :runbook_step, name: "Second") }

    after { runbook.destroy }

    it "is the last PREV_OUTPUT_LIMIT chars of the previous stage's stage_completed output" do
      first.log_run!("stage_completed", output: "x" * 10 + "y" * described_class::PREV_OUTPUT_LIMIT)
      runbook.update!(current_stage_id: second.id)

      expect(described_class.for(runbook)["{PREV_OUTPUT}"]).to eq("y" * described_class::PREV_OUTPUT_LIMIT)
    end

    it "is empty on the first stage" do
      runbook.update!(current_stage_id: first.id)
      expect(described_class.for(runbook)["{PREV_OUTPUT}"]).to eq("")
    end

    it "is empty when the previous stage has no stage_completed run" do
      first.log_run!("started")
      runbook.update!(current_stage_id: second.id)
      expect(described_class.for(runbook)["{PREV_OUTPUT}"]).to eq("")
    end

    it "is empty for non-runbook workflows" do
      expect(described_class.for(workflow)["{PREV_OUTPUT}"]).to eq("")
    end
  end
end
