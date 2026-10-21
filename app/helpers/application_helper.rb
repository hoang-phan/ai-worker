module ApplicationHelper
  # Skill names available to a project's agent: each subdirectory of
  # <local_directory>/.agents/skills.

  def project_skill_names(project)
    dir = File.join(File.expand_path(project.local_directory.to_s), ".agents", "skills")
    Dir.children(dir).select { |name| File.directory?(File.join(dir, name)) && !name.start_with?(".") }.sort
  rescue SystemCallError
    []
  end

  def time_ago_or_never(time)
    time ? "#{time_ago_in_words(time)} ago" : "never"
  end
end
