require "net/http"

module Jira
  class HttpTransport
    def call(request, uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 5,
        read_timeout: 15
      ) { |http| http.request(request) }
    end
  end
end
