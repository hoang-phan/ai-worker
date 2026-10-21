module Projects
  # Parses Project#slack_user_map: one `github-login=SlackUserID` per line (commas
  # also separate entries, `:` also accepted as the separator), used to tag
  # reviewers in Slack. Login matching is case-insensitive; the first entry with
  # an id wins.
  class SlackUserMap
    ENTRY_SEPARATOR = /[\n,]+/
    PAIR_SEPARATOR = /[=:]/

    def initialize(text)
      @text = text.to_s
    end

    def slack_id_for(github_login)
      wanted = github_login.to_s.delete_prefix("@")
      @text.split(ENTRY_SEPARATOR).each do |entry|
        login, id = entry.split(PAIR_SEPARATOR, 2).map(&:strip)
        return id if id.present? && login.to_s.casecmp?(wanted)
      end
      nil
    end
  end
end
