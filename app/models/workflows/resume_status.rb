module Workflows
  class ResumeStatus
    def initialize(workflow)
      @workflow = workflow
    end

    # The in-flight status an errored workflow goes back to: reviewing once a PR
    # exists (personal-project and PR-review workflows never reach it), otherwise implementing.
    def call
      return :uat_testing if @workflow.uat_test_at.present?

      ci_status = Workflows::CiLoopResume.new(@workflow).status
      return ci_status if ci_status
      return :local_testing if local_test_unfinished?

      @workflow.development? && @workflow.github_pr_url.present? ? :reviewing : :implementing
    end

    private

    # An errored workflow whose newest local test run started but never finished goes back to it, not to review
    # (also true for a retest after a fix round: earlier completed rounds don't count).
    def local_test_unfinished?
      @workflow.stages.find_by(stage_type: :local_test)&.local_test_unfinished? || false
    end
  end
end
