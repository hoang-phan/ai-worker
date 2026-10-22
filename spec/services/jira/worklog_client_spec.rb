require "rails_helper"

RSpec.describe Jira::WorklogClient do
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |request, uri|
      requests << [ request, uri ]
      responses.shift || raise("unexpected Jira request")
    end
  end

  subject(:client) do
    described_class.new("https://example.atlassian.net/", email: "me@example.com", token: "tok", transport: transport)
  end

  def response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  def captured_request
    requests.last.first
  end

  describe "#add_worklog" do
    it "posts the worklog and returns its id" do
      responses << response(201, { id: "99" })

      id = client.add_worklog("SPEC-1", started_at: Time.new(2026, 10, 20, 9, 30, 0, "+07:00"), seconds: 5400)

      expect(id).to eq("99")
      expect(captured_request).to be_a(Net::HTTP::Post)
      expect(captured_request.path).to eq("/rest/api/3/issue/SPEC-1/worklog")
      expect(JSON.parse(captured_request.body)).to eq("started" => "2026-10-20T09:30:00.000+0700", "timeSpentSeconds" => 5400)
    end

    it "raises WorklogError on a non-201 response" do
      responses << response(400, {})

      expect { client.add_worklog("SPEC-1", started_at: Time.current, seconds: 60) }.to raise_error(Jira::WorklogError, /Jira worklog for SPEC-1 failed \(HTTP 400\)/) { |e| expect(e.reason).to be_nil }
    end

    [ Errno::ECONNREFUSED, Timeout::Error, SocketError ].each do |error|
      it "maps #{error} to WorklogError" do
        allow(transport).to receive(:call).and_raise(error)

        expect { client.add_worklog("SPEC-1", started_at: Time.current, seconds: 60) }.to raise_error(Jira::WorklogError, /Jira request failed/)
      end
    end

    it "raises WorklogError without credentials" do
      expect { described_class.new("https://x.atlassian.net", email: nil, token: nil).add_worklog("SPEC-1", started_at: Time.current, seconds: 60) }.to raise_error(Jira::WorklogError, /not set/) { |e| expect(e.reason).to eq(:missing_credentials) }
    end
  end

  describe "#my_worklogs" do
    it "returns only the authenticated user's worklogs, following pages" do
      me = { accountId: "me-1" }
      other = { accountId: "other-2" }
      responses.concat([
        response(200, { accountId: "me-1" }),
        response(200, { total: 4, worklogs: [ { id: "1", author: me, started: "2026-10-19T09:00:00.000+0700", timeSpentSeconds: 3600 },
                                                { id: "2", author: other, started: "2026-10-19T09:00:00.000+0700", timeSpentSeconds: 7200 },
                                                { id: "3", author: me, started: "2026-10-20T10:00:00.000+0700", timeSpentSeconds: 1800 } ] }),
        response(200, { total: 4, worklogs: [ { id: "4", author: me, started: "2026-10-21T08:30:00.000+0700", timeSpentSeconds: 900 } ] })
      ])

      worklogs = client.my_worklogs("SPEC-1")

      expect(worklogs.map { |w| w.values_at(:id, :seconds) }).to eq([ [ "1", 3600 ], [ "3", 1800 ], [ "4", 900 ] ])
      expect(worklogs.first[:started]).to eq(Time.utc(2026, 10, 19, 2, 0))
      expect(requests).to have_attributes(size: 3)
    end

    it "raises WorklogError on a non-200 response" do
      responses.concat([ response(200, { accountId: "me-1" }), response(404, {}) ])

      expect { client.my_worklogs("SPEC-1") }.to raise_error(Jira::WorklogError, /SPEC-1 could not be read \(HTTP 404\)/)
    end

    it "raises WorklogError without credentials" do
      expect { described_class.new("https://x.atlassian.net", email: nil, token: nil).my_worklogs("SPEC-1") }.to raise_error(Jira::WorklogError, /not set/) { |e| expect(e.reason).to eq(:missing_credentials) }
    end
  end

  describe "#set_original_estimate_if_blank" do
    it "updates the estimate when it is 0 or missing" do
      responses.concat([ response(200, { fields: { timetracking: {} } }), response(204, nil) ])

      expect(client.set_original_estimate_if_blank("SPEC-1", 5400)).to be(true)
      expect(requests).to have_attributes(size: 2)
    end

    it "raises WorklogError on a non-204 update response" do
      responses.concat([ response(200, { fields: { timetracking: {} } }), response(403, {}) ])

      expect { client.set_original_estimate_if_blank("SPEC-1", 5400) }.to raise_error(Jira::WorklogError, /estimate update for SPEC-1 failed \(HTTP 403\)/)
    end

    it "leaves an existing estimate alone" do
      responses << response(200, { fields: { timetracking: { originalEstimateSeconds: 7200 } } })

      expect(client.set_original_estimate_if_blank("SPEC-1", 5400)).to be(false)
      expect(requests).to have_attributes(size: 1)
    end
  end

  describe "#keys_with_my_worklogs_since" do
    it "collects the keys of every result page" do
      responses.concat([
        response(200, { issues: [ { key: "A-1" } ], nextPageToken: "t2", isLast: false }),
        response(200, { issues: [ { key: "B-2" } ], isLast: true })
      ])

      expect(client.keys_with_my_worklogs_since(Date.new(2026, 10, 18))).to eq(%w[A-1 B-2])
    end
  end
end
