require "spec_helper"

module RequestSpecMirror
  # Every controller under app/controllers must have a mirrored request spec at
  # spec/requests/<same path without _controller>_spec.rb. Concerns are shared
  # controller behaviour rather than endpoints, so they are out of scope.
  EXEMPT = [
    # Rails base — no actions of its own
    "app/controllers/application_controller.rb"
  ].freeze
end

RSpec.describe "request spec mirror" do
  def controller_files
    Dir.glob("app/controllers/**/*_controller.rb").sort
  end

  def mirror_spec_for(controller_path)
    "spec/requests/#{controller_path.delete_prefix("app/controllers/").delete_suffix("_controller.rb")}_spec.rb"
  end

  it "has a mirrored request spec for every controller outside EXEMPT" do
    missing = controller_files.reject do |path|
      RequestSpecMirror::EXEMPT.include?(path) || File.exist?(mirror_spec_for(path))
    end

    expect(missing).to be_empty,
      "Missing mirrored request specs (add spec/requests/<path>_spec.rb, or EXEMPT with a reason):\n#{missing.map { |p| "  #{p} => #{mirror_spec_for(p)}" }.join("\n")}"
  end

  it "keeps EXEMPT accurate (entry exists and still has no mirrored request spec)" do
    gone = RequestSpecMirror::EXEMPT.reject { |path| File.exist?(path) }
    now_mirrored = RequestSpecMirror::EXEMPT.select do |path|
      File.exist?(path) && File.exist?(mirror_spec_for(path))
    end

    expect(gone).to be_empty,
      "EXEMPT entries no longer exist (remove them):\n#{gone.map { |p| "  #{p}" }.join("\n")}"
    expect(now_mirrored).to be_empty,
      "EXEMPT entries now have mirrored request specs (remove them from EXEMPT):\n#{now_mirrored.map { |p| "  #{p} => #{mirror_spec_for(p)}" }.join("\n")}"
  end
end
