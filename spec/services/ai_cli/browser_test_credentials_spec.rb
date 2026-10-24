require "rails_helper"

RSpec.describe AiCli::BrowserTestCredentials do
  let(:project) do
    Project.new(name: "Acme", uat_url: "https://uat.test", uat_username: "u", uat_password: "p",
                local_url: "http://localhost:3000", local_username: "lu", local_password: "lp")
  end

  def credentials_for(kind) = described_class.new(project, kind: kind)

  describe "#validate!" do
    {
      uat: { url: :uat_url, user: :uat_username, pass: :uat_password, label: "UAT" },
      local: { url: :local_url, user: :local_username, pass: :local_password, label: "local" }
    }.each do |kind, fields|
      it "requires a #{kind} URL" do
        project[fields[:url]] = ""
        expect { credentials_for(kind).validate! }.to raise_error(ArgumentError, "project Acme has no #{fields[:label]} URL")
      end

      %i[user pass].each do |field|
        it "requires a #{kind} #{field}" do
          project[fields[field]] = nil
          expect { credentials_for(kind).validate! }
            .to raise_error(ArgumentError, "project Acme has no #{fields[:label]} login (username/password)")
        end
      end

      it "passes with everything set for #{kind}" do
        credentials = credentials_for(kind)
        expect(credentials.validate!).to equal(credentials)
        expect(credentials.url).to eq(project[fields[:url]])
        expect(credentials.env).to eq(
          "#{kind.to_s.upcase}_USERNAME" => project[fields[:user]],
          "#{kind.to_s.upcase}_PASSWORD" => project[fields[:pass]]
        )
      end
    end

    it "rejects unknown kinds" do
      expect { credentials_for(:other) }.to raise_error(ArgumentError, "unknown browser test kind :other")
    end
  end
end
