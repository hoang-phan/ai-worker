require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::Planner do
  def project(dir) = Project.new(local_directory: dir)

  def workflow(id, project, kind: :development, position: id, **attrs)
    Workflow.new(id: id, project: project, kind: kind, position: position, **attrs)
  end

  describe ".clone_key" do
    it "treats '~/x', 'x/' and a symlink as the same clone" do
      tmp = make_tmpdir("planner-spec")
      real = File.join(tmp, "clone")
      FileUtils.mkdir_p(real)
      link = File.join(tmp, "link")
      File.symlink(real, link)

      home_dir = Dir.mktmpdir("clone-home", Dir.home)
      begin
        keys = [ real, "#{real}/", link, "#{tmp}/./clone" ].map { |dir| described_class.clone_key(project(dir)) }
        expect(keys.uniq).to eq([ File.realpath(real) ])

        tilde = "~/#{File.basename(home_dir)}"
        expect(described_class.clone_key(project(tilde))).to eq(described_class.clone_key(project("#{home_dir}/")))
      ensure
        FileUtils.remove_entry(home_dir)
      end
    end

    it "falls back to the expanded path when the directory does not exist" do
      expect(described_class.clone_key(project("/nonexistent/ai-worker-x/"))).to eq("/nonexistent/ai-worker-x")
    end
  end

  describe ".eligible_waiting" do
    let_tmpdir(:dir, "planner-spec")
    let(:proj) { project(dir) }

    def eligible(active, waiting, run_workflow_id: nil)
      described_class.eligible_waiting(active_workflows: active, waiting: waiting, run_workflow_id: run_workflow_id)
    end

    it "only lets the lowest-position development workflow on a clone start" do
      first = workflow(1, proj)
      second = workflow(2, project("#{dir}/"))
      expect(eligible([ first, second ], [ first, second ])).to eq([ first ])
    end

    it "lets the head of each clone start" do
      other = make_tmpdir("planner-spec")
      a = workflow(1, proj)
      b = workflow(2, project(other))
      expect(eligible([ a, b ], [ a, b ])).to eq([ a, b ])
    end

    it "keeps a PR-review workflow eligible while a development head on the clone waits on review" do
      head = workflow(1, proj, status: :reviewing)
      review = workflow(2, proj, kind: :pr_review)
      expect(eligible([ head, review ], [ review ])).to eq([ review ])
    end

    it "starts runbooks only with auto_run or when named by run_workflow_id" do
      idle = workflow(1, proj, kind: :runbook)
      auto = workflow(2, proj, kind: :runbook, auto_run: true)
      expect(eligible([ idle, auto ], [ idle, auto ])).to eq([ auto ])
      expect(eligible([ idle, auto ], [ idle, auto ], run_workflow_id: 1)).to eq([ idle, auto ])
    end

    it "does not let runbooks hold the development slot" do
      runbook = workflow(1, proj, kind: :runbook)
      dev = workflow(2, proj)
      expect(eligible([ runbook, dev ], [ dev ])).to eq([ dev ])
    end
  end
end
