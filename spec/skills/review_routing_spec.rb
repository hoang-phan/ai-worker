require "spec_helper"

module ReviewRouting
  REVIEW_SKILL_PATH = ".agents/skills/ai-worker-review/SKILL.md".freeze
  CLI_SELECTION_SKILL_PATH = ".agents/skills/ai-worker-cli-selection/SKILL.md".freeze
  PROVIDER_ADAPTER_TRIGGERS = %w[
    app/services/ai_cli/provider/{claude,codex,cursor}.rb
    spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb
  ].freeze
  JIRA_REST_CLIENT_TRIGGERS = %w[
    app/services/jira/{http_transport,rest_client,worklog_client,worklog_error}.rb
    spec/services/jira/{http_transport,rest_client,worklog_client,worklog_error}_spec.rb
  ].freeze
end

RSpec.describe "review skill routing" do
  def review_skill_text
    File.read(ReviewRouting::REVIEW_SKILL_PATH)
  end

  def cli_selection_skill_text
    File.read(ReviewRouting::CLI_SELECTION_SKILL_PATH)
  end

  def routing_rows
    review_skill_text.lines.filter_map do |line|
      cells = line.strip.split("|").map(&:strip)
      skill_name = cells.last[/\A`(ai-worker-[a-z0-9-]+)`\z/, 1] if cells.length >= 3

      [ cells[1], skill_name ] if skill_name
    end
  end

  def skill_names
    Dir.children(".agents/skills").select do |name|
      File.directory?(File.join(".agents/skills", name))
    end.sort
  end

  it "routes every subsystem skill" do
    routed_skills = routing_rows.map(&:last)
    text_outside_table = review_skill_text.lines.reject { |line| line.start_with?("   |") }.join
    missing_skills = skill_names.reject do |skill_name|
      skill_name == "ai-worker-review" || routed_skills.include?(skill_name) ||
        (skill_name == "ai-worker-refactoring" && text_outside_table.include?("`#{skill_name}`"))
    end

    expect(missing_skills).to be_empty, "Missing review routing skills:\n#{missing_skills.join("\n")}"
  end

  it "uses each skill in only one routing row" do
    duplicate_skills = routing_rows.map(&:last).tally.select { |_, count| count > 1 }.keys

    expect(duplicate_skills).to be_empty, "Duplicate review routing skills:\n#{duplicate_skills.join("\n")}"
  end

  it "routes provider adapters and their mirrored specs to CLI selection before the ai_cli fallback" do
    cli_selection_row_index = routing_rows.index { |_, skill_name| skill_name == "ai-worker-cli-selection" }
    ai_cli_fallback_index = routing_rows.index { |path, skill_name| path == "`app/services/ai_cli/**`, `app/services/ci/**`, `app/services/stages/run_tooling.rb`, or their listed specs" && skill_name == "ai-worker-agent-cli" }
    cli_selection_row = routing_rows.fetch(cli_selection_row_index).first

    expect(cli_selection_row_index).to be < ai_cli_fallback_index
    expect(cli_selection_row).to include("app/services/ai_cli/provider/{claude,codex,cursor}.rb")
    expect(cli_selection_row).to include("spec/services/ai_cli/provider/{claude,codex,cursor}_spec.rb")
  end

  it "lists every provider adapter and mirrored spec as a CLI-selection trigger" do
    ReviewRouting::PROVIDER_ADAPTER_TRIGGERS.each do |path|
      expect(cli_selection_skill_text).to include(path)
    end
  end

  it "routes Jira REST client paths and mirrored specs before the worklog fallback" do
    rest_client_row_index = routing_rows.index { |_, skill_name| skill_name == "ai-worker-jira-rest-client" }
    worklogs_row_index = routing_rows.index { |_, skill_name| skill_name == "ai-worker-jira-worklogs" }
    rest_client_row = routing_rows.fetch(rest_client_row_index).first

    expect(rest_client_row_index).to be < worklogs_row_index
    ReviewRouting::JIRA_REST_CLIENT_TRIGGERS.each { |path| expect(rest_client_row).to include(path) }
  end

  it "keeps the spec fallback as the last routing row" do
    expect(routing_rows.last).to eq([ "any `spec/**` not already matched above", "ai-worker-testing" ])
  end
end
