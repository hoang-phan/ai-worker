require "rails_helper"

RSpec.describe Scheduling::GuardedExecutor do
  let(:logger) { instance_double(Logger, error: nil) }
  let(:workflow) { instance_double(Workflow, id: 42) }

  it "calls the executor with the workflow" do
    executed = []
    described_class.new(executor: ->(w) { executed << w }, logger: logger).call(workflow)

    expect(executed).to eq([ workflow ])
    expect(logger).not_to have_received(:error)
  end

  it "logs and swallows StandardError" do
    executor = ->(_w) { raise ArgumentError, "boom" }

    expect { described_class.new(executor: executor, logger: logger).call(workflow) }.not_to raise_error
    expect(logger).to have_received(:error).with("[scheduler] workflow=42 ArgumentError: boom")
  end
end
