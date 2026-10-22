require "rails_helper"

RSpec.describe Jira::WorklogClient do
  subject(:client) { described_class.new("https://example.atlassian.net/", email: "me@example.com", token: "tok") }

  def response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  describe "#my_worklogs" do
    it "returns only the authenticated user's worklogs, following pages" do
      me = { accountId: "me-1" }
      other = { accountId: "other-2" }
      pages = [
        response(200, { accountId: "me-1" }),
        response(200, { total: 4, worklogs: [ { id: "1", author: me, started: "2026-10-19T09:00:00.000+0700", timeSpentSeconds: 3600 },
                                              { id: "2", author: other, started: "2026-10-19T09:00:00.000+0700", timeSpentSeconds: 7200 },
                                              { id: "3", author: me, started: "2026-10-20T10:00:00.000+0700", timeSpentSeconds: 1800 } ] }),
        response(200, { total: 4, worklogs: [ { id: "4", author: me, started: "2026-10-21T08:30:00.000+0700", timeSpentSeconds: 900 } ] })
      ]
      allow(Net::HTTP).to receive(:start).and_return(*pages)

      worklogs = client.my_worklogs("SPEC-1")

      expect(worklogs.map { |w| w.values_at(:id, :seconds) }).to eq([ [ "1", 3600 ], [ "3", 1800 ], [ "4", 900 ] ])
      expect(worklogs.first[:started]).to eq(Time.utc(2026, 10, 19, 2, 0))
      expect(Net::HTTP).to have_received(:start).exactly(3).times
    end

    it "raises WorklogError on a non-200 response" do
      allow(Net::HTTP).to receive(:start).and_return(response(200, { accountId: "me-1" }), response(404, {}))

      expect { client.my_worklogs("SPEC-1") }.to raise_error(Jira::WorklogError, /SPEC-1 could not be read \(HTTP 404\)/)
    end

    it "raises WorklogError without credentials" do
      expect { described_class.new("https://x.atlassian.net", email: nil, token: nil).my_worklogs("SPEC-1") }.to raise_error(Jira::WorklogError, /not set/)
    end
  end

  describe "#set_original_estimate_if_blank" do
    it "updates the estimate when it is 0 or missing" do
      allow(Net::HTTP).to receive(:start).and_return(response(200, { fields: { timetracking: {} } }), response(204, nil))

      expect(client.set_original_estimate_if_blank("SPEC-1", 5400)).to be(true)
      expect(Net::HTTP).to have_received(:start).twice
    end

    it "leaves an existing estimate alone" do
      allow(Net::HTTP).to receive(:start).and_return(response(200, { fields: { timetracking: { originalEstimateSeconds: 7200 } } }))

      expect(client.set_original_estimate_if_blank("SPEC-1", 5400)).to be(false)
      expect(Net::HTTP).to have_received(:start).once
    end
  end

  describe "#keys_with_my_worklogs_since" do
    it "collects the keys of every result page" do
      allow(Net::HTTP).to receive(:start).and_return(
        response(200, { issues: [ { key: "A-1" } ], nextPageToken: "t2", isLast: false }),
        response(200, { issues: [ { key: "B-2" } ], isLast: true })
      )

      expect(client.keys_with_my_worklogs_since(Date.new(2026, 10, 18))).to eq(%w[A-1 B-2])
    end
  end
end
