module AiCli
  # Reads the markers the agent prints in its log (see the stage prompts). Pure: no I/O, no workflow state.
  class Output
    def initialize(text)
      @text = text.to_s
    end

    # Single-line `VAR: NAME=value`, or a multi-line value between `VAR_BEGIN: NAME` and `VAR_END` lines.
    def variables
      blocks = text.scan(/^[ \t]*VAR_BEGIN:[ \t]*([A-Za-z][A-Za-z0-9_]*)[ \t]*\n(.*?)\n?^[ \t]*VAR_END[ \t]*$/m)
      lines = text.gsub(/^[ \t]*VAR_BEGIN:.*?^[ \t]*VAR_END[ \t]*$/m, "")
                  .scan(/^\s*VAR:\s*([A-Za-z][A-Za-z0-9_]*)=(.*)$/)
      (lines + blocks).to_h { |name, value| [ name.upcase, value.strip ] }
    end

    # "UAT" / "RELEASEABLE" (as written), or nil.
    def jira_result
      text[/JIRA_RESULT:\s*(UAT|RELEASEABLE)/i, 1]
    end

    # "PASSED" / "FAILED" / "BLOCKED" (as written), or nil.
    def uat_result
      text[/UAT_RESULT:\s*(PASSED|FAILED|BLOCKED)/i, 1]
    end

    # "PASSED" / "FAILED" / "BLOCKED" (as written), or nil.
    def local_test_result
      text[/LOCAL_TEST_RESULT:\s*(PASSED|FAILED|BLOCKED)/i, 1]
    end

    # The last LOCAL_RETEST line wins; a missing one counts as YES.
    def retest_requested?
      !text.scan(/LOCAL_RETEST:\s*(YES|NO)/i).last&.first.to_s.casecmp?("NO")
    end

    # The last block between the markers (the log may echo the prompt's own example), or nil.
    def local_test_feedback_block
      text.scan(/LOCAL_TEST_FEEDBACK_BEGIN[ \t]*\n(.*?)\n[ \t]*LOCAL_TEST_FEEDBACK_END/m).last&.first.to_s.strip.presence
    end

    # The last block between the markers, or nil.
    def fixed_summary
      text.scan(/FIXED_SUMMARY_BEGIN[ \t]*\n(.*?)\n[ \t]*FIXED_SUMMARY_END/m).last&.first.to_s.strip.presence
    end

    # A line that is only POSTED.
    def posted?
      text.match?(/^\s*POSTED\s*$/)
    end

    private

    attr_reader :text
  end
end
