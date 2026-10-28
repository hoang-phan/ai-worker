module AiCli
  # Reads the markers the agent prints in its log (see the stage prompts); claude's own result event is AiCli::ClaudeResult. Pure: no I/O, no workflow state.
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
      marker("JIRA_RESULT", %w[UAT RELEASEABLE])
    end

    # "PASSED" / "FAILED" / "BLOCKED" (as written), or nil.
    def uat_result
      marker("UAT_RESULT", %w[PASSED FAILED BLOCKED])
    end

    # "PASSED" / "FAILED" / "BLOCKED" (as written), or nil.
    def local_test_result
      marker("LOCAL_TEST_RESULT", %w[PASSED FAILED BLOCKED])
    end

    # "PASSED" / "FAILED" (upcased) from the last CI_VERDICT line (the log echoes the prompt's own example), or nil.
    def ci_verdict
      last_marker("CI_VERDICT", %w[PASSED FAILED])&.upcase
    end

    # The last LOCAL_RETEST line wins; a missing one counts as YES.
    def retest_requested?
      !last_marker("LOCAL_RETEST", %w[YES NO]).to_s.casecmp?("NO")
    end

    # The last block between the markers (the log may echo the prompt's own example), or nil.
    def local_test_feedback_block
      last_block("LOCAL_TEST_FEEDBACK_BEGIN", "LOCAL_TEST_FEEDBACK_END").to_s.strip.presence
    end

    # The last block between the markers, or nil.
    def fixed_summary
      last_block("FIXED_SUMMARY_BEGIN", "FIXED_SUMMARY_END").to_s.strip.presence
    end

    # The lines of the last LESSONS_BEGIN/LESSONS_END block (the log may echo the prompt's own example), without
    # their leading "- " and blank lines.
    def lessons
      block = last_block("LESSONS_BEGIN", "LESSONS_END", anchored: true).to_s
      block.lines.map { |line| line.strip.delete_prefix("- ").strip }.reject(&:blank?)
    end

    # Raw rows of the last FOLLOW_UPS_BEGIN/FOLLOW_UPS_END block (the log may echo the prompt's own example): a JSON array,
    # or [] when the block is missing, invalid JSON, or not an array.
    def follow_ups
      body = last_block("FOLLOW_UPS_BEGIN", "FOLLOW_UPS_END", anchored: true)
      rows = JSON.parse(body.to_s)
      rows.is_a?(Array) ? rows : []
    rescue JSON::ParserError
      []
    end

    # A line that is only POSTED.
    def posted?
      text.match?(/^\s*POSTED\s*$/)
    end

    private

    attr_reader :text

    def marker(name, values)
      text[marker_pattern(name, values), 1]
    end

    def last_marker(name, values)
      text.scan(marker_pattern(name, values)).last&.first
    end

    def last_block(begin_marker, end_marker, anchored: false)
      pattern = if anchored
        /^[ \t]*#{Regexp.escape(begin_marker)}[ \t]*\n(.*?)\n?^[ \t]*#{Regexp.escape(end_marker)}[ \t]*$/m
      else
        /#{Regexp.escape(begin_marker)}[ \t]*\n(.*?)\n[ \t]*#{Regexp.escape(end_marker)}/m
      end
      text.scan(pattern).last&.first
    end

    def marker_pattern(name, values)
      Regexp.new("#{Regexp.escape(name)}:\\s*(#{Regexp.union(values).source})", Regexp::IGNORECASE)
    end
  end
end
