require "rails_helper"

RSpec.describe Github::Client, "facade" do
  let(:project) { Project.new(name: "Github facade spec", kind: :personal, local_directory: Dir.tmpdir, repo_full_name: "acme/widgets") }
  let(:reader) { instance_double(Github::Reader) }
  let(:writer) { instance_double(Github::Writer) }
  let(:client) { described_class.new(project, reader: reader, writer: writer) }

  it "delegates query operations to the injected reader" do
    allow(reader).to receive_messages(merged?: true, pr_title: "T", review_decision: "APPROVED")

    expect(client.merged?("u")).to be(true)
    expect(client.pr_title("u")).to eq("T")
    expect(client.review_decision("u", [ "a" ])).to eq("APPROVED")
  end

  it "delegates side-effecting operations to the injected writer" do
    allow(writer).to receive(:request_review!)
    allow(writer).to receive(:enable_auto_merge!)

    client.request_review!("u", [ "a" ])
    client.enable_auto_merge!("u")

    expect(writer).to have_received(:request_review!).with("u", [ "a" ])
    expect(writer).to have_received(:enable_auto_merge!).with("u")
  end

  it "builds default collaborators and keeps constants" do
    default = described_class.new(project)

    expect(default.reader).to be_a(Github::Reader)
    expect(default.writer).to be_a(Github::Writer)
    expect(described_class::FAILED_STATES).to eq(Github::FailingChecks::FAILED_STATES)
  end
end
