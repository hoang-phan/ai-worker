# Temp directories that are removed after the example. Cleanup only ever removes a path under Dir.tmpdir that still exists.
module TmpDirHelper
  module ClassMethods
    # Defines a lazily created tmp dir as a `let`, e.g. `let_tmpdir(:local_directory, "transitions-spec")`.
    def let_tmpdir(name, prefix)
      let(name) { make_tmpdir(prefix) }
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  def make_tmpdir(prefix)
    Dir.mktmpdir(prefix).tap { |path| register_tmpdir(path) }
  end

  # Registers an existing path for guarded removal after the example.
  def register_tmpdir(path)
    @tmpdirs_to_remove ||= []
    @tmpdirs_to_remove << path
    path
  end

  def remove_tmpdirs
    Array(@tmpdirs_to_remove).each do |path|
      FileUtils.remove_entry(path) if path.start_with?(Dir.tmpdir) && File.exist?(path)
    end
    @tmpdirs_to_remove = nil
  end
end

RSpec.configure do |config|
  config.include TmpDirHelper
  config.after { remove_tmpdirs }
end
