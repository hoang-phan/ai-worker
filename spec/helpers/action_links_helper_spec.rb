require "rails_helper"

RSpec.describe ActionLinksHelper, type: :helper do
  describe "#delete_link_to" do
    it "renders a destructive link with a confirmation" do
      html = helper.delete_link_to("Delete", "/items/1", class: "link-danger", confirm: "Delete this item?")

      expect(html).to eq('<a class="link-danger" data-turbo-method="delete" data-turbo-confirm="Delete this item?" href="/items/1">Delete</a>')
    end

    it "omits the confirmation attribute when none is supplied" do
      html = helper.delete_link_to("Remove", "/items/1", class: "link-danger")

      expect(html).to eq('<a class="link-danger" data-turbo-method="delete" href="/items/1">Remove</a>')
    end
  end

  describe "#inline_button_to" do
    it "renders an inline button form" do
      html = helper.inline_button_to("Run", "/items/1", method: :post, class: "btn")

      expect(html).to include('<form style="display:inline" class="button_to" method="post" action="/items/1">')
      expect(html).to include('<button class="btn" type="submit">Run</button>')
    end

    it "merges existing form options" do
      html = helper.inline_button_to("Remove", "/items/1", method: :delete, form: { data: { turbo_confirm: "Remove it?" } })

      expect(html).to include('style="display:inline"')
      expect(html).to include('data-turbo-confirm="Remove it?"')
    end
  end
end
