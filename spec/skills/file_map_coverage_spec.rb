require "spec_helper"

RSpec.describe "skill file maps" do
  APP_LAYERS = %w[models services controllers helpers jobs].freeze
  EXEMPT_FILES = %w[
    app/models/application_record.rb
    app/jobs/application_job.rb
    app/controllers/application_controller.rb
    app/helpers/application_helper.rb
    app/mailers/application_mailer.rb
  ].freeze

  def skill_text
    Dir.glob(".agents/skills/*/SKILL.md").sort.flat_map do |path|
      File.readlines(path).flat_map do |line|
        [ line, *line.scan(%r{[A-Za-z0-9_./{}*,:-]+}).flat_map { |token| expand_braces(token) } ]
      end
    end.join("\n")
  end

  def expand_braces(text)
    match = text.match(/\{([^{}]+)\}/)
    return [ text ] unless match

    match[1].split(",").flat_map do |choice|
      expand_braces(text.sub(match[0], choice))
    end
  end

  def constant_name(path)
    path.delete_prefix("app/").delete_suffix(".rb").split("/").map do |part|
      part.split("_").map(&:capitalize).join
    end.join("::")
  end

  def referenced?(path, text)
    relative_path = path.sub(%r{\Aapp/(?:#{APP_LAYERS.join("|")})/}, "")
    directory_glob = relative_path.split("/").first + "/**"

    text.include?(path) || text.include?(relative_path) ||
      text.include?(directory_glob) || text.include?(constant_name(path))
  end

  it "maps every production Ruby file to a skill" do
    text = skill_text
    app_files = APP_LAYERS.flat_map do |layer|
      Dir.glob("app/#{layer}/**/*.rb")
    end.sort
    unmapped = app_files.reject do |path|
      EXEMPT_FILES.include?(path) || referenced?(path, text)
    end

    expect(unmapped).to be_empty, "Unmapped app files:\n#{unmapped.join("\n")}"
  end
end
