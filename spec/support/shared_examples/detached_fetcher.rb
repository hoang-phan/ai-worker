# Shared coverage for services that delegate run state to an AiCli::DetachedRun.
# Include from a fetcher spec with these lets:
#
#   run     - a FakeDetachedRun
#   fetcher - the service built with `run: run`
RSpec.shared_examples "a detached-run fetcher" do
  it "delegates running? and last_started_at to the run" do
    time = Time.utc(2026, 1, 1)
    run.last_started_at = time
    allow(run).to receive(:running?).and_return(true)

    expect(fetcher.running?).to be(true)
    expect(fetcher.last_started_at).to eq(time)
  end
end
