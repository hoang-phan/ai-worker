require "rails_helper"

RSpec.describe Brainstorm::Prompt do
  def build(**overrides)
    described_class.new(
      goal: "Raise test coverage", max_workflows: 4, backlog_lines: [], total_in_flight: 0,
      result_file: "/tmp/brainstorm/result.json", history_file: "/tmp/brainstorm/history.md", **overrides
    ).to_s
  end

  it "includes the goal and the result path" do
    text = build
    expect(text).to include("Raise test coverage")
    expect(text).to include("The only file you may write is /tmp/brainstorm/result.json.")
  end

  it "renders '(none yet)' for an empty backlog" do
    text = build
    expect(text).to include("(none yet)")
    expect(text).not_to include("older ones")
  end

  it "caps the backlog and hints at older ones only when the total exceeds it" do
    lines = (1..35).map { |i| "- item #{i}" }
    text = build(backlog_lines: lines, total_in_flight: 35)
    expect(text).to include("- item 30")
    expect(text).not_to include("- item 31")
    expect(text).to include("5 older ones are in /tmp/brainstorm/history.md;")
  end

  it "omits the hint when everything is shown" do
    text = build(backlog_lines: [ "- a", "- b" ], total_in_flight: 2)
    expect(text).to include("- a\n- b")
    expect(text).not_to include("older ones")
  end

  it "describes the optional skills key" do
    text = build
    expect(text).to include('"skills"')
    expect(text).to include(".agents/skills/*/SKILL.md")
    expect(text).to include("omit the key when none fit")
  end

  it "interpolates max_workflows and the summary length" do
    text = build
    expect(text).to include("propose up to 4 new")
    expect(text).to include("\"<=#{Workflow::SUMMARY_LENGTH} chars")
  end
end
