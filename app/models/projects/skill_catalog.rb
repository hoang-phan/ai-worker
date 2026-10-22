module Projects
  # Skills available to a project's agent: each non-hidden subdirectory of
  # <local_directory>/.agents/skills.
  class SkillCatalog
    def initialize(local_directory)
      @local_directory = local_directory.to_s
    end

    def dir
      File.join(File.expand_path(@local_directory), ".agents", "skills")
    end

    def names
      return [] if @local_directory.blank?

      Dir.children(dir).select { |name| File.directory?(File.join(dir, name)) && !name.start_with?(".") }.sort
    rescue SystemCallError
      []
    end
  end
end
