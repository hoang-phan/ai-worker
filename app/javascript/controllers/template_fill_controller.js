import { Controller } from "@hotwired/stimulus"

// Fills the prompt from the selected template, substituting workflow placeholders.
export default class extends Controller {
  static targets = ["select", "input"]
  static values = { placeholders: Object }

  fill() {
    let body = this.selectTarget.options[this.selectTarget.selectedIndex]?.dataset.body
    if (!body) return

    Object.keys(this.placeholdersValue).forEach((token) => {
      body = body.split(token).join(this.placeholdersValue[token])
    })

    this.inputTarget.value = body
  }
}
