module ApplicationHelper
  def time_ago_or_never(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end
end
