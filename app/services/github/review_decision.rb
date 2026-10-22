module Github
  # Determines a review outcome from GitHub's latest review for each reviewer.
  class ReviewDecision
    def self.call(latest_reviews, reviewers)
      wanted = reviewers.map { |reviewer| reviewer.to_s.downcase }
      states = latest_reviews.filter_map do |review|
        login = review.dig("author", "login").to_s.downcase
        review["state"] if wanted.empty? || wanted.include?(login)
      end

      return "APPROVED" if states.include?("APPROVED")
      return "CHANGES_REQUESTED" if states.include?("CHANGES_REQUESTED")

      nil
    end
  end
end
