require "rails_helper"

RSpec.describe "BugsnagSyncs", type: :request do
  let(:local_directory) { Dir.mktmpdir("bugsnag-syncs-request-spec") }
  let(:project) { Project.create!(name: "Spec project", kind: :jira, repo_full_name: "org/repo", local_directory: local_directory) }

  after { FileUtils.remove_entry(local_directory) if local_directory.start_with?(Dir.tmpdir) && File.exist?(local_directory) }

  describe "POST create" do
    it "re-renders the error summary when invalid" do
      expect {
        post project_bugsnag_syncs_path(project), params: { bugsnag_sync: { bugsnag_project: "", jira_project: "", min_events: 0, max_tickets: 0 } }
      }.not_to change(BugsnagSync, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      summary = Nokogiri::HTML(response.body).at_css(".error-summary").text
      expect(summary).to include("prevented this sync from saving", "Bugsnag project can't be blank")
    end
  end
end
