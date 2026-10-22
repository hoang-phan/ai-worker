require "rails_helper"

RSpec.describe Jira::WorklogClient do
  subject(:client) { described_class.new("https://example.atlassian.net/", email: "me@example.com", token: "tok") }

  def response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  describe "#logged_seconds" do
    it "sums the worklogs of every author, following pages" do
      pages = [
        response(200, { total: 3, worklogs: [ { timeSpentSeconds: 3600 }, { timeSpentSeconds: 1800 } ] }),
        response(200, { total: 3, worklogs: [ { timeSpentSeconds: 900 } ] })
      ]
      allow(Net::HTTP).to receive(:start).and_return(*pages)

      expect(client.logged_seconds("SPEC-1")).to eq(6300)
      expect(Net::HTTP).to have_received(:start).twice
    end

    it "raises WorklogError on a non-200 response" do
      allow(Net::HTTP).to receive(:start).and_return(response(404, {}))

      expect { client.logged_seconds("SPEC-1") }.to raise_error(Jira::WorklogError, /SPEC-1 could not be read \(HTTP 404\)/)
    end

    it "raises WorklogError without credentials" do
      expect { described_class.new("https://x.atlassian.net", email: nil, token: nil).logged_seconds("SPEC-1") }.to raise_error(Jira::WorklogError, /not set/)
    end
  end
end
