require "rails_helper"
require "tmpdir"

RSpec.describe Projects::LiveCheckout do
  def live?(directory, app_root)
    described_class.new(directory, app_root: app_root).live?
  end

  it "is live for the app root itself" do
    Dir.mktmpdir do |root|
      expect(live?(root, root)).to be(true)
    end
  end

  it "is live for a symlink to the app root" do
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |links|
        link = File.join(links, "clone")
        File.symlink(root, link)
        expect(live?(link, root)).to be(true)
      end
    end
  end

  it "is not live for a different directory" do
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |other|
        expect(live?(other, root)).to be(false)
      end
    end
  end

  it "is not live for a missing directory" do
    Dir.mktmpdir do |root|
      expect(live?(File.join(root, "nope"), root)).to be(false)
    end
  end

  it "is not live when blank" do
    Dir.mktmpdir do |root|
      expect(live?("", root)).to be(false)
      expect(live?(nil, root)).to be(false)
    end
  end
end
