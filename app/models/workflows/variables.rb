module Workflows
  # Pure helpers for a runbook's variables: the `NAME=value` per line text form used by the UI, and telling the
  # variables a user typed apart from the ones stages emitted. The DB lookup of stage outputs stays in Workflow.
  class Variables
    # One `NAME=value` per line; newlines inside a value are written as a literal \n.
    def self.to_text(hash)
      hash.map { |name, value| "#{name}=#{value.to_s.gsub("\n", "\\n")}" }.join("\n")
    end

    # Inverse of to_text: names are upcased, lines without a name are dropped, only the first `=` splits.
    def self.parse(text)
      text.to_s.lines.filter_map do |line|
        name, value = line.strip.split("=", 2)
        [ name.strip.upcase, value.to_s.strip.gsub("\\n", "\n") ] if name.present?
      end.to_h
    end

    # Names that stage outputs emitted via `VAR:` lines or `VAR_BEGIN`/`VAR_END` blocks.
    def self.output_names(outputs)
      outputs.flat_map { |output| AiCli::Output.new(output).variables.keys }.uniq
    end

    # The variables without anything the given stage outputs emitted.
    def self.input_only(variables, outputs)
      variables.except(*output_names(outputs))
    end
  end
end
