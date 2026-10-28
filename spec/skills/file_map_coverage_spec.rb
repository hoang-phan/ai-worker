require "spec_helper"
require_relative "../support/skill_path_helper"

module FileMapCoverage
  APP_LAYERS = %w[models services controllers helpers jobs].freeze
  NON_RUBY_APP_GLOBS = [
    "app/views/**/*.erb",
    "app/views/pwa/*",
    "app/javascript/controllers/*_controller.js",
    "app/services/prompts/defaults/*.md",
    "app/assets/stylesheets/*.css"
  ].freeze
  EXEMPT_FILES = %w[
    app/models/application_record.rb
    app/jobs/application_job.rb
    app/controllers/application_controller.rb
    app/helpers/application_helper.rb
    app/mailers/application_mailer.rb
  ].freeze
end

RSpec.describe "skill file maps" do
  include SkillPathHelper

  def skill_text
    Dir.glob(".agents/skills/*/SKILL.md").sort.flat_map do |path|
      File.readlines(path).flat_map do |line|
        [ line, *line.scan(%r{[A-Za-z0-9_./{}*,:-]+}).flat_map { |token| expand_braces(token) } ]
      end
    end.join("\n")
  end

  def constant_name(path)
    path.delete_prefix("app/").delete_suffix(".rb").split("/").map do |part|
      part.split("_").map(&:capitalize).join
    end.join("::")
  end

  def referenced?(path, text)
    relative_path = path.sub(%r{\Aapp/(?:#{FileMapCoverage::APP_LAYERS.join("|")})/}, "")
    directory_glob = relative_path.split("/").first + "/**"

    text.include?(path) || text.include?(relative_path) ||
      text.include?(directory_glob) || text.include?(constant_name(path))
  end

  def non_ruby_referenced?(path, text)
    path_parts = path.split("/")
    view_directory_globs = if path.start_with?("app/views/")
      (3...path_parts.length).map { |length| path_parts.first(length).join("/") + "/**" }
    else
      []
    end

    text.include?(path) || view_directory_globs.any? { |glob| text.include?(glob) }
  end

  it "maps every production Ruby file to a skill" do
    text = skill_text
    app_files = FileMapCoverage::APP_LAYERS.flat_map do |layer|
      Dir.glob("app/#{layer}/**/*.rb")
    end.sort
    unmapped = app_files.reject do |path|
      FileMapCoverage::EXEMPT_FILES.include?(path) || referenced?(path, text)
    end

    expect(unmapped).to be_empty, "Unmapped app files:\n#{unmapped.join("\n")}"
  end

  it "maps every production view, Stimulus controller, default prompt, and stylesheet to a skill" do
    text = skill_text
    exempt_files = %w[
      app/javascript/application.js
      app/javascript/controllers/application.js
      app/javascript/controllers/index.js
      app/views/layouts/mailer.html.erb
      app/views/layouts/mailer.text.erb
    ]
    app_files = FileMapCoverage::NON_RUBY_APP_GLOBS.flat_map { |glob| Dir.glob(glob) }.sort
    unmapped = app_files.reject do |path|
      exempt_files.include?(path) || non_ruby_referenced?(path, text)
    end

    expect(unmapped).to be_empty, "Unmapped non-Ruby app files:\n#{unmapped.join("\n")}"
  end
end
