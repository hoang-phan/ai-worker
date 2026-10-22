require "rails_helper"

RSpec.describe Github::Runner do
  let(:project) { Project.new(repo_full_name: "acme/widgets", local_directory: "/tmp/acme-widgets") }
  let(:calls) { [] }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:result) { [ "out", "", status ] }
  let(:capture) do
    lambda do |*argv, **opts|
      calls << { argv: argv, opts: opts }
      result
    end
  end

  subject(:runner) { described_class.new(project, capture: capture) }

  it "appends -R <repo_full_name> by default" do
    runner.run!([ "gh", "pr", "view", "feature" ])

    expect(calls.last[:argv]).to eq([ "gh", "pr", "view", "feature", "-R", "acme/widgets" ])
  end

  it "uses a custom repo when given" do
    runner.run!([ "gh", "pr", "list" ], repo: "other/repo")

    expect(calls.last[:argv]).to eq([ "gh", "pr", "list", "-R", "other/repo" ])
  end

  it "leaves the command untouched with scope_to_repo: false" do
    runner.run!([ "gh", "api", "repos/acme/widgets/pulls" ], scope_to_repo: false)

    expect(calls.last[:argv]).to eq([ "gh", "api", "repos/acme/widgets/pulls" ])
  end

  it "runs in the project's local directory" do
    runner.run!([ "gh", "pr", "list" ])

    expect(calls.last[:opts]).to eq(chdir: "/tmp/acme-widgets")
  end

  it "returns stdout on success" do
    expect(runner.run!([ "gh", "pr", "list" ])).to eq("out")
  end

  context "when the command fails" do
    let(:status) { instance_double(Process::Status, success?: false) }

    context "with stderr" do
      let(:result) { [ "some out", "boom", status ] }

      it "raises CommandError with the joined command and stderr" do
        expect { runner.run!([ "gh", "pr", "list" ]) }
          .to raise_error(Github::CommandError, "gh pr list -R acme/widgets failed: boom")
      end
    end

    context "with blank stderr" do
      let(:result) { [ "some out", "", status ] }

      it "falls back to stdout" do
        expect { runner.run!([ "gh", "api", "x" ], scope_to_repo: false) }
          .to raise_error(Github::CommandError, "gh api x failed: some out")
      end
    end
  end
end
