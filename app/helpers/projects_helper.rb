module ProjectsHelper
  ICON_PATHS = {
    external_link: "M14 3h7v7h-2V6.41l-9.29 9.3-1.42-1.42L17.59 5H14V3Zm5 16H5V5h7V3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7h-2v7Z",
    edit: "m3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25ZM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83Z"
  }.freeze

  def project_header_meta(project)
    parts = [ project.local_directory ]
    parts << " · #{project.repo_full_name}" if project.repo_full_name.present?
    safe_join(parts)
  end

  def show_brainstorm_section?(project)
    project.personal? && (project.brainstorm_enabled? || project.brainstorm_goal.present?)
  end

  def show_slack_reviews_section?(project)
    project.jira? && (project.slack_review_enabled? || project.slack_mention.present?)
  end

  def workflow_status_filter_options
    [ [ "All", "" ] ] + Workflow.statuses.keys.map { |status| [ status.humanize, status ] }
  end

  def workflow_list_empty_message(workflow_list)
    return "No workflows yet." unless workflow_list.status_filter

    "No #{workflow_list.status_filter.humanize.downcase} workflows."
  end

  def icon_svg(name)
    %(<svg viewBox="0 0 24 24" aria-hidden="true"><path d="#{ICON_PATHS.fetch(name)}"/></svg>).html_safe
  end
end
