# Shared examples for "run now" request actions that consult a blockers list and
# then start a background agent run. Include from a request spec that has
# stubbed the collaborators, and define these lets:
#
#   perform_request  - lambda that issues the request (e.g. -> { post run_path })
#   starter          - the double whose `start` is called
#   blockers_owner   - the double whose `blockers` is stubbed
#   blocked_blockers - blockers array to stub (e.g. [ "no token" ])
#   blocked_alert    - expected alert for those blockers
#   started_notice   - expected notice when start returns true
#   running_alert    - expected alert when start returns false
#   start_error      - exception instance raised from start
#   failed_alert     - expected alert for that exception
#
# Examples that only apply to one action (e.g. brainstorm's pending-skip) stay
# in the including spec.
RSpec.shared_examples "a manual start action" do
  it "reports the blockers" do
    allow(blockers_owner).to receive(:blockers).and_return(blocked_blockers)

    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:alert]).to eq(blocked_alert)
    expect(starter).not_to have_received(:start)
  end

  it "starts the run" do
    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:notice]).to eq(started_notice)
  end

  it "says when a run is already running" do
    allow(starter).to receive(:start).and_return(false)

    instance_exec(&perform_request)

    expect(flash[:alert]).to eq(running_alert)
  end

  it "reports a failed start" do
    allow(starter).to receive(:start).and_raise(start_error)

    instance_exec(&perform_request)

    expect(response).to redirect_to(project_path(project))
    expect(flash[:alert]).to eq(failed_alert)
  end
end
