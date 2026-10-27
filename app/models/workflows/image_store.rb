module Workflows
  # Reference images live as plain, unencoded files on disk (not Active
  # Storage) so the agent CLI can read them straight from the path
  # substituted into the {IMAGES} placeholder.
  class ImageStore
    DEFAULT_ROOT = AgentRuns::StateRoot.join("workflow_images")
    EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .bmp .svg].freeze

    def initialize(workflow_id:, root: DEFAULT_ROOT)
      @root = Pathname(root)
      @workflow_id = workflow_id
    end

    def dir
      @root.join(@workflow_id.to_s)
    end

    def paths
      return [] unless dir.directory?

      dir.children.select(&:file?).sort.map(&:to_s)
    end

    # `uploads` are ActionDispatch::Http::UploadedFile-like objects (original_filename, read).
    # Non-images are skipped; returns the number saved.
    def add(uploads)
      saved = 0
      Array.wrap(uploads).each do |upload|
        next unless upload.respond_to?(:original_filename)

        name = File.basename(upload.original_filename.to_s).gsub(/[^\w.\-]/, "_")
        next unless EXTENSIONS.include?(File.extname(name).downcase)

        FileUtils.mkdir_p(dir)
        File.binwrite(unique_path(name), upload.read)
        saved += 1
      end
      saved
    end

    def remove(name)
      path = dir.join(File.basename(name.to_s))
      FileUtils.rm_f(path) if path.file?
    end

    def purge!
      FileUtils.rm_rf(dir)
    end

    private

    def unique_path(name)
      path = dir.join(name)
      return path unless path.exist?

      ext = File.extname(name)
      dir.join("#{File.basename(name, ext)}-#{SecureRandom.hex(3)}#{ext}")
    end
  end
end
