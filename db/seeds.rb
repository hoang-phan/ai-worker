# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Default prompt for Slack-driven PR-review workflows (adapted from the
# review-prs-from-slack skill). Only created if absent — edits made in the UI
# are never overwritten.
PromptTemplate.find_or_create_by!(name: "PR Review", stage_type: :pr_review) do |template|
  template.body = PromptTemplate::DEFAULT_PR_REVIEW_BODY
end

# Example runbook workflow: the Recruit release process, as a pending "template" run on a Recruit project.
# Each release is a new runbook workflow on the project that copies these stages ("Start with the stages of"),
# so every deployment keeps its own stage list. Created only if absent, so edits are never overwritten.
# Set RECRUIT_DIR to a real directory for the agent's working directory (defaults to this app's own checkout).
project = Project.find_or_create_by!(name: "Recruit") do |p|
  p.kind = :personal
  p.local_directory = ENV.fetch("RECRUIT_DIR", Rails.root.to_s)
end
if project.workflows.runbook.none?
  workflow = project.workflows.create!(
    kind: :runbook,
    variables: { "REGION" => "CA", "REPO" => "net-engine/scout", "PROJECT_NAME" => "Recruit", "CSS_GROUP" => "<!subteam^S039ALMP4TS>", "VERSION" => "", "RELEASE_DATE" => "", "CHANNEL" => "#client-success-and-product-teams" }
  )
  [
    [ "Fetch and filter release items", :agent, nil, File.read(Rails.root.join("db/seeds/release_notes_prompt.md")) ],
    [ "Comms: testing in UAT", :message, "{CHANNEL}", "{CSS_GROUP} Release day! 🚀 Tickets for testing in UAT:\n{RELEASE_ITEMS}" ],
    [ "Comms: deploy in 10 minutes", :message, "{CHANNEL}", "Thanks for merging and labelling your PRs. {REGION} Recruit will be deployed in the next 10 minutes." ],
    [ "Create release tickets", :agent, nil, <<~P ],
      Create the Support Board tickets "Recruit {REGION} Release {RELEASE_DATE}" and "QA Recruit {REGION} Release {RELEASE_DATE}"
      with the Atlassian MCP tools. Both need the tags Client:Scout, Project:Recruit, Type:Task, Release.
      Report the ticket keys; do not assign anyone unless told to.
    P
    [ "Find build version", :agent, nil, <<~P ],
      With `gh`, find the latest successful "Main Deploy" run on main, and in its "Build Image" step the version passed to
      build-production.sh (format 2.xx.y-<hash>). End your reply with a line exactly like: VAR: VERSION=2.21.1-f839742
    P
    [ "Comms: deploying", :message, "{CHANNEL}", "Deploying {REGION} Recruit. Version `{VERSION}`." ],
    [ "Comms: deployment complete", :message, "{CHANNEL}", "Deployment complete. Starting QA." ],
    [ "Comms: QA complete", :message, "{CHANNEL}", "QA complete, all flows passed. @css-team" ]
  ].each_with_index do |(name, mode, channel, prompt), index|
    workflow.stages.create!(stage_type: :runbook_step, name: name, position: index + 1, run_mode: mode, channel: channel, prompt: prompt)
  end
end
