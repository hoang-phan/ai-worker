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

  # Data for a row's selection checkbox: only development workflows can log time, and only those with
  # nothing logged yet are "fresh" (targets of "Select all non time logged").
  def workflow_selection_data(workflow, seconds)
    log_time = workflow.development?
    { range_select_target: "box", action: "click->range-select#click", log_time: log_time, fresh: log_time && !seconds.to_i.positive? }
  end

  # Seconds logged in Jira as hours, e.g. 5400 => "1.5", 3600 => "1".
  def logged_hours(seconds)
    number_with_precision(seconds.to_i / 3600.0, precision: 2, strip_insignificant_zeros: true)
  end
end
