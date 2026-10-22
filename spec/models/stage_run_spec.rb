require "rails_helper"

RSpec.describe StageRun, type: :model do
  subject(:stage_run) { described_class.new(action: action) }

  let(:action) { "started" }

  describe "ACTIONS" do
    it "has no duplicates" do
      expect(described_class::ACTIONS.uniq).to eq(described_class::ACTIONS)
    end
  end

  describe "action validation" do
    context "when the action is nil" do
      let(:action) { nil }

      it "is required" do
        stage_run.valid?

        expect(stage_run.errors[:action]).to include("can't be blank")
      end
    end

    context "when the action is not in ACTIONS" do
      let(:action) { "not_a_real_action" }

      it "is rejected" do
        stage_run.valid?

        expect(stage_run.errors[:action]).to include("is not included in the list")
      end
    end

    StageRun::ACTIONS.each do |known_action|
      context "when the action is #{known_action}" do
        let(:action) { known_action }

        it "is accepted" do
          stage_run.valid?

          expect(stage_run.errors[:action]).to be_empty
        end
      end
    end
  end
end
