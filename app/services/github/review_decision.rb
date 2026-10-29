module Github
  # Determines a review outcome from GitHub's latest review for each reviewer. A COMMENTED review counts as a change
  # request: GitHub's latestReviews reports it in place of an earlier CHANGES_REQUESTED from the same reviewer.
  class ReviewDecision
    def self.call(latest_reviews, reviewers)
      wanted = reviewers.map { |reviewer| reviewer.to_s.downcase }
      states = latest_reviews.filter_map do |review|
        login = review.dig("author", "login").to_s.downcase
        review["state"] if wanted.empty? || wanted.include?(login)
      end

      return "APPROVED" if states.include?("APPROVED")
      return "CHANGES_REQUESTED" if (states & %w[CHANGES_REQUESTED COMMENTED]).any?

      nil
    end
  end
end
