module Jira
  # Pure helpers for turning a Jira ticket URL / key into the pieces the app needs.
  module TicketRef
    KEY_PATTERN = /[A-Z][A-Z0-9]+-\d+/

    module_function

    # "https://x.atlassian.net/browse/UIUX-3456?foo=1" -> "UIUX-3456"
    def branch_name_for(url)
      url.to_s.split("browse/").last.to_s.split(%r{[/?#]}).first
    end

    # Ticket key ("UIUX-3456") for a stored jira_ticket (URL or bare key); nil when none is found.
    def key_for(jira_ticket)
      branch_name_for(jira_ticket).to_s[KEY_PATTERN]
    end

    def url_for(base_url, key)
      "#{base_url.to_s.chomp("/")}/browse/#{key}"
    end
  end
end
