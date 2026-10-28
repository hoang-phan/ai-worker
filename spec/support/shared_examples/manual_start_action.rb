# Shared examples for "run now" request actions that consult a blockers list and
# then start a background agent run through the real controller → CycleSource →
# sync/planner → fetcher/RunLifecycle → AiCli::DetachedRun chain. Stub only
# AiCli::Runner.start / .poll (the documented subprocess boundary). Define:
#
#   perform_request  - lambda that issues the request (e.g. -> { post run_path })
#   make_blocked     - setup that makes the real blockers non-empty
#   make_running     - setup that makes the underlying run appear alive
#   make_failing     - setup that makes start raise AiCli::CommandError
#   blocked_alert    - expected alert when blocked
#   started_notice   - expected notice when start succeeds
#   running_alert    - expected alert when already running
#   failed_alert     - expected alert when start fails
#
# The including example group should leave the record ready to start (empty
# blockers) and stub AiCli::Runner.start to return a fake pid for the happy path.
# Examples that only apply to one action (e.g. brainstorm's pending-skip) stay
# in the including spec.
RSpec.shared_examples "a manual start action" do
  it "reports the blockers" do
    instance_exec(&make_blocked)

    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:alert]).to eq(blocked_alert)
  end

  it "starts the run" do
    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:notice]).to eq(started_notice)
  end

  it "says when a run is already running" do
    instance_exec(&make_running)

    instance_exec(&perform_request)

    expect(flash[:alert]).to eq(running_alert)
  end

  it "reports a failed start" do
    instance_exec(&make_failing)

    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:alert]).to eq(failed_alert)
  end
end
