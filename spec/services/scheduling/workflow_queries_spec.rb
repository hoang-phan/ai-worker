require "rails_helper"
require "tmpdir"

RSpec.describe Scheduling::WorkflowQueries do
  let(:now) { Time.zone.parse("2026-10-28 10:00:00") }

  def project
    directory = make_tmpdir("workflow-queries-spec")
    build_personal_project(local_directory: directory)
  end

  def workflow(status: :implementing, position: 1, project: self.project, **attributes)
    build_task_workflow(project, status: status, kind: :development, position: position,
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
    it "is false when no agent is running, whatever the statuses" do
      workflow(status: :reviewing)
      workflow(status: :done, position: 2)
      workflow(status: :implementing, position: 3)
      workflow(status: :local_testing, position: 4)

      expect(described_class.work_in_progress?).to be(false)
    end

    it "is true when any workflow is processing" do
      running = workflow(status: :implementing)
      running.update!(processing: true)

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
    it "includes a workflow exactly at now, but not one second before its due time" do
      due_now = workflow(status: :uat_waiting, uat_test_at: now)

      expect(described_class.due_uat_tests(limit: 5, now: now - 1.second)).to be_empty
      expect(described_class.due_uat_tests(limit: 5, now: now).to_a).to eq([ due_now ])
    end

    it "includes due uat_waiting and idle uat_testing, ordered by uat_test_at" do
      retry_run = workflow(status: :uat_testing, position: 1, uat_test_at: now - 3.hours)
      due = workflow(status: :uat_waiting, position: 2, uat_test_at: now - 2.hours)
      oldest = workflow(status: :uat_waiting, position: 3, uat_test_at: now - 4.hours)

      expect(described_class.due_uat_tests(limit: 5, now: now).to_a).to eq([ oldest, retry_run, due ])
    end

    it "excludes uat_waiting not yet due and processing uat_testing" do
      workflow(status: :uat_waiting, position: 1, uat_test_at: now + 1.hour)
      workflow(status: :uat_testing, position: 2, processing: true, uat_test_at: now - 1.hour)

      expect(described_class.due_uat_tests(limit: 5, now: now)).to be_empty
    end

    it "includes uat_testing that is not processing" do
      idle = workflow(status: :uat_testing, uat_test_at: now - 1.hour)

      expect(described_class.due_uat_tests(limit: 5, now: now).to_a).to eq([ idle ])
    end

    it "respects the limit" do
      workflow(status: :uat_waiting, position: 1, uat_test_at: now - 3.hours)
      workflow(status: :uat_waiting, position: 2, uat_test_at: now - 2.hours)

      expect(described_class.due_uat_tests(limit: 1, now: now).size).to eq(1)
    end
  end
end
