require "open3"

module Git
  # Runs `git` in a directory and translates failures into CommandError. Always
  # passes `chdir:` with an argument array — never a `cd X && ...` string.
  class Shell
    def initialize(directory)
      @directory = directory
    end

    # Returns [out, err, status] without raising.
    def run(command)
      Open3.capture3(*command, chdir: directory)
    end

    def run!(command)
      out, err, status = run(command)
      raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}" unless status.success?

      out
    end

    def success?(command)
      _out, _err, status = run(command)
      status.success?
    end

    # Runs a `git checkout`. If it is refused because local changes (tracked or
    # untracked) would be overwritten, stashes them (nothing is discarded —
    # recover with `git stash list` / `git stash pop`) and retries once.
    def checkout!(command)
      out, err, status = run(command)
      return out if status.success?

      unless err.match?(/would be overwritten by checkout/)
        raise CommandError, "#{command.join(' ')} failed: #{err.presence || out}"
      end

      run!([ "git", "stash", "push", "--include-untracked", "-m", "ai-worker: auto-stash before #{command.join(' ')}" ])
      run!(command)
    end

    private

    attr_reader :directory
  end
end
