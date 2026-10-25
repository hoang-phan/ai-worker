require "rails_helper"

RSpec.describe Projects::SettingsParams do
  describe ".call" do
    it "permits the exact settings attributes from every section" do
      attributes = described_class::GENERAL_ATTRIBUTES +
        described_class::INSTRUCTIONS_ATTRIBUTES +
        described_class::JIRA_ATTRIBUTES +
        described_class::SLACK_ATTRIBUTES +
        described_class::UAT_TEST_ATTRIBUTES +
        described_class::CI_LOOP_ATTRIBUTES +
        described_class::LOCAL_TEST_ATTRIBUTES +
        described_class::BRAINSTORM_ATTRIBUTES
      expected_attributes = %i[
        name local_directory repo_full_name kind default_skills default_pr_skills default_reviewers
        ci_instructions test_instructions agent_lessons
        jira_base_url jira_assignee jira_tester
        slack_review_enabled slack_mention slack_review_channel slack_user_map
        uat_test_enabled uat_url uat_instructions uat_username uat_password uat_test_delay_minutes
        flow ci_command ci_max_rounds ci_verify_instructions pr_instructions
        local_test_enabled local_url local_instructions local_username local_password
        brainstorm_enabled brainstorm_goal brainstorm_max_workflows brainstorm_auto_start
      ]
      params = ActionController::Parameters.new(project: attributes.index_with { |attribute| "value for #{attribute}" })

      permitted = described_class.call(params)

      expect(attributes).to eq(expected_attributes)
      expect(permitted).to be_permitted
      expect(permitted.to_h).to eq(expected_attributes.index_with { |attribute| "value for #{attribute}" }.stringify_keys)
    end

    it "rejects unknown and system-managed fields" do
      params = ActionController::Parameters.new(project: {
        name: "Acme", unknown_setting: "no", id: 12, brainstorm_last_result: "system result", created_at: Time.current
      })

      expect(described_class.call(params).to_h).to eq("name" => "Acme")
    end

    it "raises when the project root is absent" do
      expect {
        described_class.call(ActionController::Parameters.new(name: "Acme"))
      }.to raise_error(ActionController::ParameterMissing, /project/)
    end

    it "removes absent and blank password submissions while preserving blank non-secret values" do
      params = ActionController::Parameters.new(project: {
        uat_password: "", local_password: "", uat_username: "", local_instructions: ""
      })

      expect(described_class.call(params).to_h).to eq("uat_username" => "", "local_instructions" => "")
      expect(described_class.call(ActionController::Parameters.new(project: { name: "Acme" })).to_h).to eq("name" => "Acme")
    end

    it "preserves nonblank password submissions" do
      params = ActionController::Parameters.new(project: { uat_password: "uat secret", local_password: "local secret" })

      expect(described_class.call(params).to_h).to eq("uat_password" => "uat secret", "local_password" => "local secret")
    end
  end
end
