require "rails_helper"

RSpec.describe "Layout", type: :request do
  describe "GET index" do
    it "links each app stylesheet from the layout" do
      get projects_path

      expect(response).to have_http_status(:ok)
      stylesheet_hrefs = Nokogiri::HTML(response.body).css('link[rel="stylesheet"]').map { |node| node["href"] }
      %w[
        01_base
        02_navigation
        03_page_layout
        04_flash
        05_cards
        06_tables
        07_badges
        08_buttons
        09_forms
        10_misc
      ].each do |name|
        expect(stylesheet_hrefs).to include(a_string_matching(%r{/assets/#{name}(-[a-f0-9]+)?\.css\z}))
      end
    end
  end
end
