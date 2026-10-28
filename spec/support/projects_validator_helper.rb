# Shared setup for Projects::Validator specs (mirrored and concern files).
# Include in each RSpec.describe Projects::Validator that needs a temp local_directory.
module ProjectsValidatorHelper
  def self.included(base)
    base.let_tmpdir(:local_directory, "project-validator-spec")
  end

  def project(**attrs)
    Project.new({ name: "Spec project", kind: :personal, local_directory: local_directory }.merge(attrs))
  end

  def errors_for(record)
    record.valid?
    record.errors
  end
end
