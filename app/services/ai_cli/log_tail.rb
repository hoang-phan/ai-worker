module AiCli
  # Reads an agent run's log file incrementally across scheduler ticks and
  # mirrors each new line into Rails.logger tagged with the run.
  class LogTail
    def initialize(log_path:, log_tag:, logger: Rails.logger)
      @log_path = log_path
      @log_tag = log_tag
      @logger = logger
    end

    # Logs (and returns) any log file content written since offset.
    # Returns [content, new_offset]; pass new_offset in next time.
    def read_from(offset)
      return [ "", offset ] unless File.exist?(log_path)

      content = File.open(log_path, "rb") do |f|
        f.seek(offset)
        f.read
      end.to_s

      content.each_line { |line| log_line(line) }
      [ content, offset + content.bytesize ]
    end

    # The whole log, or "" when there is none.
    def full
      return "" unless File.exist?(log_path)

      File.read(log_path)
    end

    private

    attr_reader :log_path, :log_tag, :logger

    def log_line(line)
      logger.info("[ai_cli #{log_tag}] #{line.chomp}")
    end
  end
end
