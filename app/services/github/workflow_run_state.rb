module Github
  # Maps GitHub Actions workflow run data to the state exposed by Github::Reader.
  class WorkflowRunState
    def self.call(runs, since:)
      run = runs
        .select { |candidate| Time.zone.parse(candidate["createdAt"].to_s) >= since }
        .max_by { |candidate| candidate["createdAt"] }
      return { state: :none } unless run
      return { state: :pending, url: run["url"] } unless run["status"].to_s.casecmp?("completed")

      {
        state: run["conclusion"].to_s.casecmp?("success") ? :success : :failed,
        url: run["url"],
        conclusion: run["conclusion"]
      }
    end
  end
end
