require "open3"
require "tmpdir"

# Builds throwaway git fixtures (bare origin + clone on `main`) under
# Dir.mktmpdir. Never touches a real checkout.
module GitRepoHelper
  def git(dir, *args)
    out, err, status = Open3.capture3("git", *args, chdir: dir.to_s)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end

  def configure_git_user(dir)
    git(dir, "config", "user.name", "Test")
    git(dir, "config", "user.email", "test@example.com")
  end

  def commit_file(dir, name, content, message = "update #{name}")
    File.write(File.join(dir, name), content)
    git(dir, "add", name)
    git(dir, "commit", "-m", message)
  end

  # Returns [origin_path, clone_path]; clone is on `main` with one pushed commit.
  def build_git_fixture(root)
    origin = File.join(root, "origin.git")
    clone = File.join(root, "clone")
    git(root, "init", "--bare", "-b", "main", origin)
    git(root, "clone", origin, clone)
    configure_git_user(clone)
    git(clone, "checkout", "-B", "main")
    commit_file(clone, "README.md", "hello\n", "initial")
    git(clone, "push", "-u", "origin", "main")
    [ origin, clone ]
  end

  # A second clone of origin, used to push commits "from elsewhere".
  def build_other_clone(root, origin)
    other = File.join(root, "other")
    git(root, "clone", origin, other)
    configure_git_user(other)
    other
  end
end
