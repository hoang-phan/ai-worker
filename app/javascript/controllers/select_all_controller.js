import { Controller } from "@hotwired/stimulus"

// Header checkbox toggles every row checkbox marked data-select-all-target="row".
export default class extends Controller {
  static targets = ["row"]

  toggle(event) {
    this.rowTargets.forEach((box) => { box.checked = event.target.checked })
  }
}
