require "rails_helper"

RSpec.describe Projects::SlackUserMap do
  def id_for(text, login)
    described_class.new(text).slack_id_for(login)
  end

  it "reads newline-separated entries" do
    expect(id_for("alice=U1\nbob=U2", "bob")).to eq("U2")
  end

  it "reads comma-separated entries" do
    expect(id_for("alice=U1,bob=U2", "bob")).to eq("U2")
  end

  it "accepts ':' as the separator" do
    expect(id_for("alice:U1", "alice")).to eq("U1")
  end

  it "trims surrounding whitespace" do
    expect(id_for("  alice  =  U1  \r\n , bob = U2 ", "alice")).to eq("U1")
  end

  it "strips a leading @ from the lookup login" do
    expect(id_for("alice=U1", "@alice")).to eq("U1")
  end

  it "matches logins case-insensitively" do
    expect(id_for("Alice=U1", "aLICE")).to eq("U1")
  end

  it "returns nil for unknown logins" do
    expect(id_for("alice=U1", "carol")).to be_nil
  end

  it "returns nil for blank or nil text" do
    expect(id_for("", "alice")).to be_nil
    expect(id_for(nil, "alice")).to be_nil
  end

  it "returns nil for a nil login" do
    expect(id_for("alice=U1", nil)).to be_nil
  end

  it "ignores entries without an id" do
    expect(id_for("alice\nbob=\ncarol=U3", "alice")).to be_nil
    expect(id_for("alice\nbob=\ncarol=U3", "bob")).to be_nil
    expect(id_for("alice\nbob=\ncarol=U3", "carol")).to eq("U3")
  end

  it "uses the first entry that has an id" do
    expect(id_for("alice=\nalice=U1\nalice=U2", "alice")).to eq("U1")
  end
end
