require "rails_helper"

RSpec.describe TmpDirHelper do
  describe ".let_tmpdir" do
    let_tmpdir(:scratch, "tmp-dir-helper-spec")

    # after(:context) runs once every example hook (including the helper's cleanup) has finished.
    after(:context) { expect(File.exist?(self.class.seen_path)).to be(false), "tmpdir was not removed" }

    def self.seen_path = @seen_path
    def self.seen_path=(path)
      @seen_path = path
    end

    it "creates the dir lazily under Dir.tmpdir" do
      expect(File.directory?(scratch)).to be true
      expect(scratch).to start_with(Dir.tmpdir)
      expect(File.basename(scratch)).to start_with("tmp-dir-helper-spec")
      (Pathname(scratch) + "marker").write("x")
      self.class.seen_path = scratch
    end
  end

  describe "#make_tmpdir" do
    it "creates several dirs and removes each one after the example" do
      first = make_tmpdir("tmp-dir-helper-a")
      second = make_tmpdir("tmp-dir-helper-b")
      expect([ first, second ].map { |d| File.directory?(d) }).to eq([ true, true ])
      expect(first).not_to eq(second)
      @made = [ first, second ]
      remove_tmpdirs
      expect(@made.map { |d| File.exist?(d) }).to eq([ false, false ])
    end
  end

  describe "cleanup guard" do
    it "never removes a path outside Dir.tmpdir" do
      outside = Dir.mktmpdir("tmp-dir-helper-outside", Rails.root.join("tmp").to_s)
      begin
        expect(outside).not_to start_with(Dir.tmpdir)
        register_tmpdir(outside)
        remove_tmpdirs
        expect(File.directory?(outside)).to be true
      ensure
        FileUtils.remove_entry(outside) if File.exist?(outside)
      end
    end

    it "ignores paths that are already gone" do
      path = make_tmpdir("tmp-dir-helper-gone")
      FileUtils.remove_entry(path)
      expect { remove_tmpdirs }.not_to raise_error
    end
  end
end
