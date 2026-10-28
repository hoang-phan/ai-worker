require "rails_helper"

RSpec.describe Stages::CollaboratorFactory, type: :service do
  let(:collaborators) { { workflow: :wf, stage: :st, project: :proj, extra: :x } }

  def build(entry)
    described_class.new(collaborators).build(entry)
  end

  it "builds a [Klass, keys] pair with sliced keyword arguments" do
    klass = Class.new do
      attr_reader :kwargs

      def initialize(**kwargs)
        @kwargs = kwargs
      end
    end

    expect(build([ klass, %i[workflow stage] ]).kwargs).to eq(workflow: :wf, stage: :st)
  end

  it "calls an injected callable with every collaborator as a keyword" do
    received = nil
    entry = ->(**kwargs) { received = kwargs; :built }

    expect(build(entry)).to eq(:built)
    expect(received).to eq(collaborators)
  end
end
