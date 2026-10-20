require "rails_helper"
require "tmpdir"

RSpec.describe Workflows::ImageStore do
  Upload = Struct.new(:original_filename, :data) do
    def read = data
  end

  let(:root) { Pathname(Dir.mktmpdir("image_store_spec")) }
  let(:store) { described_class.new(root: root, workflow_id: 42) }

  after { FileUtils.rm_rf(root) }

  describe "#add" do
    it "saves images and returns the count" do
      count = store.add([ Upload.new("a.png", "1"), Upload.new("b.JPG", "2") ])

      expect(count).to eq(2)
      expect(store.paths.map { |p| File.basename(p) }).to eq(%w[a.png b.JPG])
    end

    it "skips non-image extensions and objects without original_filename" do
      count = store.add([ Upload.new("notes.txt", "x"), Object.new, "string", Upload.new("noext", "x") ])

      expect(count).to eq(0)
      expect(store.paths).to eq([])
    end

    it "accepts a single upload" do
      expect(store.add(Upload.new("a.png", "1"))).to eq(1)
    end

    it "sanitises unsafe characters and path components" do
      store.add([ Upload.new("../evil.png", "x"), Upload.new("my pic (1)$.png", "x") ])

      names = store.paths.map { |p| File.basename(p) }
      expect(names).to contain_exactly("evil.png", "my_pic__1__.png")
      expect(root.join("evil.png")).not_to exist
      expect(store.paths).to all(start_with(store.dir.to_s))
    end

    it "gives a duplicate name a random suffix instead of overwriting" do
      store.add(Upload.new("a.png", "first"))
      store.add(Upload.new("a.png", "second"))

      expect(store.paths.size).to eq(2)
      expect(File.binread(store.dir.join("a.png"))).to eq("first")
      other = store.paths.find { |p| File.basename(p) != "a.png" }
      expect(File.basename(other)).to match(/\Aa-\h{6}\.png\z/)
      expect(File.binread(other)).to eq("second")
    end

    it "works with Rack::Test::UploadedFile" do
      file = Tempfile.new([ "up", ".png" ])
      file.write("img")
      file.close
      upload = Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "real.png")

      expect(store.add(upload)).to eq(1)
      expect(File.binread(store.dir.join("real.png"))).to eq("img")
    ensure
      file&.unlink
    end
  end

  describe "#paths" do
    it "is empty when the directory does not exist" do
      expect(store.paths).to eq([])
    end

    it "returns sorted files only" do
      FileUtils.mkdir_p(store.dir.join("subdir"))
      %w[c.png a.png b.png].each { |n| File.write(store.dir.join(n), "x") }

      expect(store.paths).to eq(%w[a.png b.png c.png].map { |n| store.dir.join(n).to_s })
    end
  end

  describe "#remove" do
    it "deletes the named file" do
      store.add(Upload.new("a.png", "x"))
      store.remove("a.png")

      expect(store.paths).to eq([])
    end

    it "ignores path traversal and uses only the basename" do
      store.add(Upload.new("a.png", "x"))
      outside = root.join("secret.png")
      File.write(outside, "keep")

      store.remove("../secret.png")
      expect(outside).to exist

      store.remove("../42/a.png")
      expect(store.paths).to eq([])
    end
  end

  describe "#purge!" do
    it "deletes the directory" do
      store.add(Upload.new("a.png", "x"))
      store.purge!

      expect(store.dir).not_to exist
    end

    it "is safe when nothing exists" do
      expect { store.purge! }.not_to raise_error
    end
  end

  describe "default root" do
    it "is tmp/workflow_images under Rails.root" do
      expect(described_class.new(workflow_id: 1).dir).to eq(Rails.root.join("tmp", "workflow_images", "1"))
    end
  end
end
