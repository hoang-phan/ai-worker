require "rails_helper"

RSpec.describe Slack::WebClient do
  let(:client) { described_class.new("xoxb-fake-token") }
  let(:http) { instance_double(Net::HTTP) }
  let(:captured) { [] }

  def stub_response(code:, body:)
    response = instance_double(Net::HTTPResponse, code: code, body: body)
    allow(http).to receive(:request) { |req| captured << req; response }
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  let(:payload) { JSON.parse(captured.first.body) }

  describe "#post_message" do
    it "returns the parsed body and sends an authenticated payload with unfurls off" do
      stub_response(code: "200", body: { ok: true, ts: "1.2" }.to_json)

      expect(client.post_message(channel: "C1", text: "hi")).to eq("ok" => true, "ts" => "1.2")
      expect(Net::HTTP).to have_received(:start).with("slack.com", 443, hash_including(use_ssl: true))
      expect(captured.first["Authorization"]).to eq "Bearer xoxb-fake-token"
      expect(captured.first["Content-Type"]).to include("application/json")
      expect(payload).to eq("channel" => "C1", "text" => "hi", "unfurl_links" => false, "unfurl_media" => false)
    end

    it "includes thread_ts only when given" do
      stub_response(code: "200", body: { ok: true }.to_json)
      client.post_message(channel: "C1", text: "hi", thread_ts: "9.9")
      expect(payload["thread_ts"]).to eq "9.9"
    end

    it "omits a blank thread_ts" do
      stub_response(code: "200", body: { ok: true }.to_json)
      client.post_message(channel: "C1", text: "hi", thread_ts: "")
      expect(payload).not_to have_key("thread_ts")
    end

    it "raises NotifyError with Slack's error when ok is false" do
      stub_response(code: "200", body: { ok: false, error: "channel_not_found" }.to_json)
      expect { client.post_message(channel: "C1", text: "hi") }
        .to raise_error(Slack::NotifyError, "Slack chat.postMessage failed: channel_not_found")
    end

    it "falls back to the HTTP code when there is no error field" do
      stub_response(code: "500", body: { ok: false }.to_json)
      expect { client.post_message(channel: "C1", text: "hi") }.to raise_error(Slack::NotifyError, /failed: 500/)
    end

    it "maps invalid JSON to NotifyError" do
      stub_response(code: "200", body: "<html>oops</html>")
      expect { client.post_message(channel: "C1", text: "hi") }.to raise_error(Slack::NotifyError, /Slack request failed/)
    end

    it "maps network errors to NotifyError" do
      [ Errno::ECONNREFUSED, Timeout::Error, SocketError, OpenSSL::SSL::SSLError ].each do |error|
        allow(Net::HTTP).to receive(:start).and_raise(error)
        expect { client.post_message(channel: "C1", text: "hi") }.to raise_error(Slack::NotifyError, /Slack request failed/)
      end
    end
  end
end
