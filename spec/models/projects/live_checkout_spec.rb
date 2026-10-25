require "rails_helper"

RSpec.describe Projects::LiveCheckout do
  def live?(directory, app_root)
    described_class.new(directory, app_root: app_root).live?
  end

  it "is live for the app root itself" do
    root = make_tmpdir("live-checkout-spec")
    expect(live?(root, root)).to be(true)
  end

  it "is live for a symlink to the app root" do
    root = make_tmpdir("live-checkout-spec")
    links = make_tmpdir("live-checkout-links")
    link = File.join(links, "clone")
    File.symlink(root, link)
    expect(live?(link, root)).to be(true)
  end

  it "is not live for a different directory" do
    root = make_tmpdir("live-checkout-spec")
    other = make_tmpdir("live-checkout-other")
    expect(live?(other, root)).to be(false)
  end

  it "is not live for a missing directory" do
    root = make_tmpdir("live-checkout-spec")
    expect(live?(File.join(root, "nope"), root)).to be(false)
  end

  it "is not live when blank" do
    root = make_tmpdir("live-checkout-spec")
    expect(live?("", root)).to be(false)
    expect(live?(nil, root)).to be(false)
  end
end
