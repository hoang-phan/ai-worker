module ApplicationHelper
  def time_ago_or_never(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end

  def last_run_summary(time, result)
    [ time_ago_or_never(time), result.presence ].compact.join(" · ")
  end
end
