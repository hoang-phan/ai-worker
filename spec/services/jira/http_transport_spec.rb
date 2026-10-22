require "rails_helper"

RSpec.describe Jira::HttpTransport do
  it "uses the URI host, port, SSL setting, and Jira timeouts" do
    request = instance_double(Net::HTTP::Get)
    response = instance_double(Net::HTTPResponse)
    http = instance_double(Net::HTTP, request: response)
    uri = URI("https://example.atlassian.net/rest/api/3/myself")

    expect(Net::HTTP).to receive(:start)
      .with("example.atlassian.net", 443, use_ssl: true, open_timeout: 5, read_timeout: 15)
      .and_yield(http)

    expect(described_class.new.call(request, uri)).to be(response)
  end
end
