module Slack
  # Pure helpers for a Slack message permalink and its thread timestamp.
  module ThreadRef
    PERMALINK = %r{https://[^\s/]+\.slack\.com/archives/[A-Z0-9]+/p\d{16}(?:\?\S*)?}

    module_function

    def ts_for(value)
      text = value.to_s.strip
      text[%r{/p(\d{10})(\d{6})}] ? "#{$1}.#{$2}" : text.presence
    end
  end
end
