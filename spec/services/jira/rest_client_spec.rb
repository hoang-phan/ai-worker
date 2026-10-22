require "rails_helper"

RSpec.describe Jira::RestClient do
  let(:requests) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |request, uri|
      requests << [ request, uri ]
      responses.shift || raise("unexpected Jira request")
    end
  end
  let(:basic_auth) { "Basic #{Base64.strict_encode64('me@example.com:tok')}" }

  subject(:client) do
    described_class.new("https://example.atlassian.net/", email: "me@example.com", token: "tok", transport: transport)
  end

  def response(code, body)
    instance_double(Net::HTTPResponse, code: code.to_s, body: body.to_json)
  end

  def queries
    requests.map { |_, uri| URI.decode_www_form(uri.query.to_s).to_h }
  end

  describe "#ensure_credentials!" do
    it "passes with credentials" do
      expect { client.ensure_credentials! }.not_to raise_error
    end

    [ { email: nil, token: "tok" }, { email: "me@example.com", token: "" } ].each do |creds|
      it "raises a missing_credentials WorklogError for #{creds}" do
        rest = described_class.new("https://x.atlassian.net", **creds, transport: transport)

        expect { rest.ensure_credentials! }.to raise_error(Jira::WorklogError, "JIRA_EMAIL / JIRA_ACCESS_TOKEN are not set") { |e| expect(e.reason).to eq(:missing_credentials) }
      end
    end
  end

  describe "#get_json" do
    it "builds a GET with Accept, basic auth, an encoded query and no body" do
      responses << response(200, { ok: true })

      expect(client.get_json("/rest/api/3/issue/SPEC-1/worklog", maxResults: 1000, startAt: 0)).to eq("ok" => true)
      req, uri = requests.last

      expect(req).to be_a(Net::HTTP::Get)
      expect(uri.to_s).to start_with("https://example.atlassian.net/rest/api/3/issue/SPEC-1/worklog?")
      expect(queries.last).to eq("maxResults" => "1000", "startAt" => "0")
      expect(req["Accept"]).to eq("application/json")
      expect(req["Content-Type"]).to be_nil
      expect(req["Authorization"]).to eq(basic_auth)
      expect(req.body).to be_nil
    end

    it "omits the query without params" do
      responses << response(200, {})

      client.get_json("/rest/api/3/myself")

      expect(requests.last.last.to_s).to eq("https://example.atlassian.net/rest/api/3/myself")
    end

    it "percent-encodes query params" do
      responses << response(200, {})

      client.get_json("/rest/api/3/search/jql", jql: "a = b()")

      expect(requests.last.last.query).to eq("jql=a+%3D+b%28%29")
    end

    it "names the issue in the failure message on a non-200 response" do
      responses << response(404, {})

      expect { client.get_json("/rest/api/3/issue/SPEC-1/worklog") }.to raise_error(Jira::WorklogError, "Jira SPEC-1 could not be read (HTTP 404)") { |e| expect(e.reason).to be_nil }
    end

    it "names the path in the failure message when it has no issue" do
      responses << response(500, {})

      expect { client.get_json("/rest/api/3/myself") }.to raise_error(Jira::WorklogError, "Jira /rest/api/3/myself could not be read (HTTP 500)")
    end

    it "maps an invalid JSON response body to WorklogError" do
      responses << instance_double(Net::HTTPResponse, code: "200", body: "not json")

      expect { client.get_json("/x") }.to raise_error(Jira::WorklogError, /Jira request failed/)
    end
  end

  describe "#request" do
    it "builds a POST with Accept, Content-Type, basic auth and a JSON body" do
      responses << response(201, { id: "99" })

      result = client.request(:post, "/rest/api/3/issue/SPEC-1/worklog", body: { a: 1 }, expect: 201) { |code| "failed #{code}" }
      req, uri = requests.last

      expect(result).to eq("id" => "99")
      expect(req).to be_a(Net::HTTP::Post)
      expect(uri.to_s).to eq("https://example.atlassian.net/rest/api/3/issue/SPEC-1/worklog")
      expect(req["Accept"]).to eq("application/json")
      expect(req["Content-Type"]).to eq("application/json")
      expect(req["Authorization"]).to eq(basic_auth)
      expect(JSON.parse(req.body)).to eq("a" => 1)
    end

    it "returns nil for an empty body" do
      responses << instance_double(Net::HTTPResponse, code: "204", body: nil)

      expect(client.request(:put, "/x", body: {}, expect: 204) { |code| code }).to be_nil
      expect(requests.last.first).to be_a(Net::HTTP::Put)
    end

    it "raises the block's message when the status is not the expected one" do
      responses << response(400, {})

      expect { client.request(:post, "/x", body: {}, expect: 201) { |code| "failed (HTTP #{code})" } }.to raise_error(Jira::WorklogError, "failed (HTTP 400)")
    end

    [ Errno::ECONNREFUSED, Timeout::Error, SocketError, OpenSSL::SSL::SSLError ].each do |error|
      it "maps #{error} to WorklogError" do
        allow(transport).to receive(:call).and_raise(error)

        expect { client.request(:get, "/x", expect: 200) { |code| code } }.to raise_error(Jira::WorklogError, /Jira request failed/)
      end
    end
  end

  describe "#each_offset_page" do
    it "yields each page's data and items, advancing startAt until total" do
      responses.concat([ response(200, { total: 3, worklogs: [ { id: 1 }, { id: 2 } ] }), response(200, { total: 3, worklogs: [ { id: 3 } ] }) ])
      seen = []

      client.each_offset_page("/p", { maxResults: 1000 }) { |data, items| seen << [ data["total"], items.map { |i| i["id"] } ] }

      expect(seen).to eq([ [ 3, [ 1, 2 ] ], [ 3, [ 3 ] ] ])
      expect(queries).to eq([ { "maxResults" => "1000", "startAt" => "0" }, { "maxResults" => "1000", "startAt" => "2" } ])
    end

    it "stops on an empty page even when total says there is more" do
      responses << response(200, { total: 5, worklogs: [] })

      client.each_offset_page("/p", {}) { |_data, _items| }

      expect(requests.size).to eq(1)
    end

    it "reads items from a custom items_key" do
      responses << response(200, { total: 1, values: [ { id: 7 } ] })
      seen = []

      client.each_offset_page("/p", {}, items_key: "values") { |_data, items| seen += items }

      expect(seen).to eq([ { "id" => 7 } ])
    end
  end

  describe "#each_token_page" do
    it "follows nextPageToken until isLast" do
      responses.concat([ response(200, { issues: [ 1 ], nextPageToken: "t2", isLast: false }), response(200, { issues: [ 2 ], isLast: true }) ])
      seen = []

      client.each_token_page("/s", { jql: "x" }) { |data| seen += data["issues"] }

      expect(seen).to eq([ 1, 2 ])
      expect(queries).to eq([ { "jql" => "x" }, { "jql" => "x", "nextPageToken" => "t2" } ])
    end

    it "stops on isLast even when a token is present" do
      responses << response(200, { nextPageToken: "t2", isLast: true })

      client.each_token_page("/s", {}) { |_data| }

      expect(requests.size).to eq(1)
    end

    it "stops on a blank token" do
      responses << response(200, { nextPageToken: "" })

      client.each_token_page("/s", {}) { |_data| }

      expect(requests.size).to eq(1)
    end
  end
end
