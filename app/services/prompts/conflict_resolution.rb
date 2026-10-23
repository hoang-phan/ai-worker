module Prompts
  # Fixed prompt for the run that resolves merge conflicts left by `git merge main`.
  module ConflictResolution
    TEXT = <<~PROMPT.freeze
      The current branch is in the middle of `git merge main` and has merge conflicts.
      Resolve every conflict (find them with `git status` / `git diff --name-only --diff-filter=U`),
      keeping the intent of both sides, then `git add` the resolved files and finish the merge with
      `git commit --no-edit`. Make sure the project still builds and its tests pass. Do not push.
    PROMPT
  end
end
