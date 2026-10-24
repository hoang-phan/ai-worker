module ProjectsHelper
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
end
