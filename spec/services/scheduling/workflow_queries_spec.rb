require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::WorkflowQueries do
  let(:directories) { [] }

  after do
    directories.each do |directory|
      FileUtils.remove_entry(directory) if directory.start_with?(Dir.tmpdir) && File.exist?(directory)
    end
  end

  def project
    directory = Dir.mktmpdir("workflow-queries-spec")
    directories << directory
    Project.create!(name: "Queries spec #{SecureRandom.hex(4)}", kind: :personal, local_directory: directory)
  end

  def workflow(status: :implementing, position: 1, project: self.project, **attributes)
    project.workflows.create!(status: status, kind: :development, position: position,
                              task_description: "Task #{SecureRandom.hex(4)}", **attributes)
  end

  describe ".active" do
    it "returns implementing, reviewing and local_testing workflows in position order" do
      c = workflow(status: :local_testing, position: 3)
      a = workflow(status: :implementing, position: 1)
      b = workflow(status: :reviewing, position: 2)
      workflow(status: :done, position: 4)
      workflow(status: :merged, position: 5, processing: true)

      expect(described_class.active).to eq([ a, b, c ])
    end
  end

  describe ".polling_updates" do
    it "includes processing merged and uat_testing workflows only" do
      merged = workflow(status: :merged, position: 1, processing: true)
      uat = workflow(status: :uat_testing, position: 2, processing: true)
      workflow(status: :merged, position: 3)
      workflow(status: :uat_testing, position: 4)
      workflow(status: :implementing, position: 5, processing: true)

      expect(described_class.polling_updates).to eq([ merged, uat ])
    end

    it "includes merged+processing, which next_merged excludes" do
      merged = workflow(status: :merged, processing: true)

      expect(described_class.polling_updates).to eq([ merged ])
      expect(described_class.next_merged).to be_nil
    end
  end

  describe ".busy_clone_keys" do
    it "returns the clone key of every processing workflow, whatever its status" do
      first = project
      second = project
      workflow(project: first, status: :merged, processing: true)
      workflow(project: second, status: :implementing)

      expect(described_class.busy_clone_keys).to eq([ Scheduling::Planner.clone_key(first) ])
    end
  end

  describe ".next_merged" do
    it "returns the lowest-position non-processing merged workflow" do
      workflow(status: :merged, position: 1, processing: true)
      later = workflow(status: :merged, position: 3)
      earlier = workflow(status: :merged, position: 2)

      expect(described_class.next_merged).to eq(earlier)
      later.update!(processing: true)
      earlier.update!(processing: true)
      expect(described_class.next_merged).to be_nil
    end
  end

  describe ".work_in_progress?" do
    it "is false when idle or only reviewing/done" do
      workflow(status: :reviewing)
      workflow(status: :done, position: 2)

      expect(described_class.work_in_progress?).to be(false)
    end

    it "counts implementing, local_testing and any processing workflow" do
      implementing = workflow(status: :implementing)
      expect(described_class.work_in_progress?).to be(true)
      implementing.update!(status: :local_testing)
      expect(described_class.work_in_progress?).to be(true)
      implementing.update!(status: :reviewing)
      expect(described_class.work_in_progress?).to be(false)
      implementing.update!(processing: true)
      expect(described_class.work_in_progress?).to be(true)
    end

    it "counts local_testing on its own" do
      workflow(status: :local_testing)

      expect(described_class.work_in_progress?).to be(true)
    end
  end

  describe ".merge_candidates" do
    it "returns done development workflows with a PR url in position order" do
      b = workflow(status: :done, position: 2, github_pr_url: "https://github.com/acme/widgets/pull/2")
      a = workflow(status: :done, position: 1, github_pr_url: "https://github.com/acme/widgets/pull/1")
      workflow(status: :done, position: 3)
      workflow(status: :reviewing, position: 4, github_pr_url: "https://github.com/acme/widgets/pull/4")

      expect(described_class.merge_candidates.to_a).to eq([ a, b ])
    end
  end

  describe ".free_agent_slots" do
    it "subtracts processing workflows from the max" do
      workflow(processing: true)
      workflow(status: :merged, position: 2, processing: true)
      workflow(status: :reviewing, position: 3)

      expect(described_class.free_agent_slots(max: 3)).to eq(1)
    end
  end

  describe ".due_uat_tests" do
    it "includes due uat_waiting and idle uat_testing, ordered by uat_test_at" do
      retry_run = workflow(status: :uat_testing, position: 1, uat_test_at: 3.hours.ago)
      due = workflow(status: :uat_waiting, position: 2, uat_test_at: 2.hours.ago)
      oldest = workflow(status: :uat_waiting, position: 3, uat_test_at: 4.hours.ago)

      expect(described_class.due_uat_tests(limit: 5).to_a).to eq([ oldest, retry_run, due ])
    end

    it "excludes uat_waiting not yet due and processing uat_testing" do
      workflow(status: :uat_waiting, position: 1, uat_test_at: 1.hour.from_now)
      workflow(status: :uat_testing, position: 2, processing: true, uat_test_at: 1.hour.ago)

      expect(described_class.due_uat_tests(limit: 5)).to be_empty
    end

    it "includes uat_testing that is not processing" do
      idle = workflow(status: :uat_testing, uat_test_at: 1.hour.ago)

      expect(described_class.due_uat_tests(limit: 5).to_a).to eq([ idle ])
    end

    it "respects the limit" do
      workflow(status: :uat_waiting, position: 1, uat_test_at: 3.hours.ago)
      workflow(status: :uat_waiting, position: 2, uat_test_at: 2.hours.ago)

      expect(described_class.due_uat_tests(limit: 1).size).to eq(1)
    end
  end
end
