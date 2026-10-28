require "spec_helper"

# Every production class under app/{models,services,jobs,helpers} must have a
# mirrored focused spec at spec/<same path>_spec.rb. Controllers are out of
# scope (request specs do not mirror paths). EXEMPT is for files that are not
# usefully unit-tested on their own; prefer writing a focused spec over adding
# an exemption when the class has real behaviour.
module SpecMirror
  LAYERS = %w[models services jobs helpers].freeze

  EXEMPT = [
    # Rails base — empty subclass, no behaviour of its own
    "app/models/application_record.rb",
    # Rails base — empty subclass, no behaviour of its own
    "app/jobs/application_job.rb",
    # Error-only class (subclass of StandardError)
    "app/services/ai_cli/command_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/brainstorm/fetch_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/bugsnag/fetch_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/git/command_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/github/command_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/jira/fetch_error.rb",
    # Module-only namespace shell; section POROs have their own mirrored specs
    "app/services/prompts/stage_sections.rb",
    # Error-only class (subclass of StandardError)
    "app/services/slack/fetch_error.rb",
    # Error-only class (subclass of StandardError)
    "app/services/slack/notify_error.rb"
  ].freeze
end

RSpec.describe "spec mirror" do
  def app_files
    SpecMirror::LAYERS.flat_map { |layer| Dir.glob("app/#{layer}/**/*.rb") }.sort
  end

  def mirror_spec_for(app_path)
    "spec/#{app_path.delete_prefix("app/").delete_suffix(".rb")}_spec.rb"
  end

  it "has a mirrored spec for every production file outside EXEMPT" do
    missing = app_files.reject do |path|
      SpecMirror::EXEMPT.include?(path) || File.exist?(mirror_spec_for(path))
    end

    expect(missing).to be_empty,
      "Missing mirrored specs (add spec/<path>_spec.rb, or EXEMPT with a reason):\n#{missing.map { |p| "  #{p} => #{mirror_spec_for(p)}" }.join("\n")}"
  end

  it "keeps EXEMPT accurate (entry exists and still has no mirrored spec)" do
    gone = SpecMirror::EXEMPT.reject { |path| File.exist?(path) }
    now_mirrored = SpecMirror::EXEMPT.select { |path| File.exist?(path) && File.exist?(mirror_spec_for(path)) }

    expect(gone).to be_empty,
      "EXEMPT entries no longer exist (remove them):\n#{gone.map { |p| "  #{p}" }.join("\n")}"
    expect(now_mirrored).to be_empty,
      "EXEMPT entries now have mirrored specs (remove them from EXEMPT):\n#{now_mirrored.map { |p| "  #{p} => #{mirror_spec_for(p)}" }.join("\n")}"
  end
end
