require "rails_helper"

RSpec.describe Projects::Validator do
  include ProjectsValidatorHelper

  describe "uat_url" do
    it "allows blank when UAT testing is off" do
      expect(project(uat_url: "", uat_test_enabled: false)).to be_valid
    end

    it "must be a full HTTP URL" do
      errors = errors_for(project(uat_url: "not-a-url"))

      expect(errors.details[:uat_url]).to eq([ { error: :invalid, value: "not-a-url" } ])
      expect(errors[:uat_url]).to eq([ "must be a full URL like https://uat.example.com" ])
    end

    it "is required when UAT testing is enabled" do
      expect(errors_for(project(uat_test_enabled: true, uat_url: "")).details[:uat_url])
        .to eq([ { error: :blank } ])
    end

    it "accepts a full URL when UAT testing is enabled" do
      expect(project(uat_test_enabled: true, uat_url: "https://uat.example.com")).to be_valid
    end
  end

  describe "local_url" do
    it "allows blank when local testing is off" do
      expect(project(local_url: "", local_test_enabled: false)).to be_valid
    end

    it "must be a full HTTP URL" do
      errors = errors_for(project(local_url: "ftp://x"))

      expect(errors.details[:local_url]).to eq([ { error: :invalid, value: "ftp://x" } ])
      expect(errors[:local_url]).to eq([ "must be a full URL like http://localhost:3000" ])
    end

    it "is required when local testing is enabled" do
      expect(errors_for(project(local_test_enabled: true, local_url: "")).details[:local_url])
        .to eq([ { error: :blank } ])
    end

    it "accepts a full URL when local testing is enabled" do
      expect(project(local_test_enabled: true, local_url: "http://localhost:3000")).to be_valid
    end
  end

  describe "uat_test_delay_minutes" do
    it "rejects a negative value" do
      expect(errors_for(project(uat_test_delay_minutes: -1)).details[:uat_test_delay_minutes])
        .to eq([ { error: :greater_than_or_equal_to, value: -1, count: 0 } ])
    end

    it "accepts zero" do
      expect(project(uat_test_delay_minutes: 0)).to be_valid
    end
  end
end
