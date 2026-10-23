module TimeLogsHelper
  # "1.5 h logged in Jira — synced 5 minutes ago".
  def workflow_logged_time_label(workflow)
    [ "#{logged_hours(workflow.logged_seconds)} h logged in Jira", jira_synced_phrase(workflow) ].compact.join(" — ")
  end

  # "synced 5 minutes ago", or nil when hours have never been synced from Jira.
  def jira_synced_phrase(workflow)
    "synced #{time_ago_in_words(workflow.jira_logged_synced_at)} ago" if workflow.jira_logged_synced_at
  end

  # Logged-hours badge for development workflows; nil for other kinds.
  def workflow_logged_time_badge(workflow, seconds)
    return unless workflow.development?

    if seconds.to_i.positive?
      title = [ "Hours you have logged in Jira", jira_synced_phrase(workflow) ].compact.join(", ")
      content_tag(:span, "#{logged_hours(seconds)} h", class: "badge badge-success", title: title)
    else
      content_tag(:span, "Not logged", class: "badge badge-neutral")
    end
  end

  # Only rows with nothing logged yet are targets of the header select-all checkbox.
  def time_log_checkbox_data(seconds)
    seconds.to_i.positive? ? {} : { select_all_target: "row" }
  end

  # Seconds logged in Jira as hours, e.g. 5400 => "1.5", 3600 => "1".
  def logged_hours(seconds)
    number_with_precision(seconds.to_i / 3600.0, precision: 2, strip_insignificant_zeros: true)
  end
end
