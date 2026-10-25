class Projects::SettingsParams
  GENERAL_ATTRIBUTES = %i[
    name local_directory repo_full_name kind default_skills default_pr_skills default_reviewers
  ].freeze
  INSTRUCTIONS_ATTRIBUTES = %i[
    ci_instructions test_instructions agent_lessons
  ].freeze
  JIRA_ATTRIBUTES = %i[
    jira_base_url jira_assignee jira_tester
  ].freeze
  SLACK_ATTRIBUTES = %i[
    slack_review_enabled slack_mention slack_review_channel slack_user_map
  ].freeze
  UAT_TEST_ATTRIBUTES = %i[
    uat_test_enabled uat_url uat_instructions uat_username uat_password
    uat_test_delay_minutes
  ].freeze
  CI_LOOP_ATTRIBUTES = %i[
    flow ci_command ci_max_rounds ci_verify_instructions pr_instructions
  ].freeze
  LOCAL_TEST_ATTRIBUTES = %i[
    local_test_enabled local_url local_instructions local_username local_password
  ].freeze
  BRAINSTORM_ATTRIBUTES = %i[
    brainstorm_enabled brainstorm_goal brainstorm_max_workflows brainstorm_auto_start
  ].freeze
  KEEP_IF_BLANK = %i[uat_password local_password].freeze

  def self.call(params) = new(params).call

  def initialize(params)
    @params = params
  end

  def call
    permitted = @params.require(:project).permit(
      GENERAL_ATTRIBUTES,
      INSTRUCTIONS_ATTRIBUTES,
      JIRA_ATTRIBUTES,
      SLACK_ATTRIBUTES,
      UAT_TEST_ATTRIBUTES,
      CI_LOOP_ATTRIBUTES,
      LOCAL_TEST_ATTRIBUTES,
      BRAINSTORM_ATTRIBUTES
    )

    # The password fields are never filled in; blank means "keep the saved one".
    KEEP_IF_BLANK.each do |attribute|
      permitted.delete(attribute) if permitted[attribute].blank?
    end

    permitted
  end
end
