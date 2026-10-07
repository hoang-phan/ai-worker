class Workflow < ApplicationRecord
  belongs_to :project
  has_many :stages, dependent: :destroy

  enum :status, { pending: 0, implementing: 1, reviewing: 2, done: 3 }

  # which stage type is currently active for each in-flight workflow status
  STAGE_TYPE_BY_STATUS = { "implementing" => "implementation", "reviewing" => "pr_check" }.freeze
  # personal-project workflows have a single stage and skip "reviewing" entirely
  SIMPLE_STAGE_TYPE_BY_STATUS = { "implementing" => "task" }.freeze

  validates :jira_ticket, presence: true, if: -> { project&.team? }
  validates :branch_name, presence: true, if: -> { project&.team? }
  validates :github_reviewer, presence: true, if: -> { project&.team? }
  validates :task_description, presence: true, if: -> { project&.personal? }
  validates :github_pr_url, format: { with: %r{\Ahttps://github\.com/[^/\s]+/[^/\s]+/pull/\d+\z}, message: "must be a github.com pull request URL" }, allow_blank: true

  after_create :seed_stages
  after_destroy :purge_images

  IMAGE_ROOT = Rails.root.join("tmp", "workflow_images")
  IMAGE_EXTENSIONS = %w[.png .jpg .jpeg .gif .webp .bmp .svg].freeze

  # Reference images live as plain, unencoded files on disk (not Active
  # Storage) so the agent CLI can read them straight from the path
  # substituted into the {IMAGES} placeholder.
  def image_dir
    IMAGE_ROOT.join(id.to_s)
  end

  def image_paths
    return [] unless image_dir.directory?

    image_dir.children.select(&:file?).sort.map(&:to_s)
  end

  # `uploads` are ActionDispatch::Http::UploadedFile objects. Non-images are
  # skipped; returns the number saved.
  def add_images(uploads)
    saved = 0
    Array(uploads).each do |upload|
      next unless upload.respond_to?(:original_filename)

      name = File.basename(upload.original_filename.to_s).gsub(/[^\w.\-]/, "_")
      next unless IMAGE_EXTENSIONS.include?(File.extname(name).downcase)

      FileUtils.mkdir_p(image_dir)
      File.binwrite(unique_image_path(name), upload.read)
      saved += 1
    end
    saved
  end

  def remove_image(name)
    path = image_dir.join(File.basename(name.to_s))
    FileUtils.rm_f(path) if path.file?
  end

  # comma-separated skill names entered in the UI, rendered into the {SKILLS} placeholder
  def skill_list
    skills.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def current_stage
    mapping = project.personal? ? SIMPLE_STAGE_TYPE_BY_STATUS : STAGE_TYPE_BY_STATUS
    stage_type = mapping[status]
    return nil unless stage_type

    stages.find_by(stage_type: stage_type)
  end

  private

  def unique_image_path(name)
    path = image_dir.join(name)
    return path unless path.exist?

    ext = File.extname(name)
    image_dir.join("#{File.basename(name, ext)}-#{SecureRandom.hex(3)}#{ext}")
  end

  def purge_images
    FileUtils.rm_rf(image_dir)
  end

  def seed_stages
    if project.personal?
      stages.create!(stage_type: :task)
    else
      stages.create!(stage_type: :implementation)
      stages.create!(stage_type: :pr_check)
    end
  end
end
