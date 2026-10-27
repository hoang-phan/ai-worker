import { Controller } from "@hotwired/stimulus"

// Shows the number of ticked workflows, enables "Delete selected" and sets its confirm dialog text.
export default class extends Controller {
  static targets = ["count", "submit"]

  update() {
    const count = document.querySelectorAll('input[form="bulk-delete-form"][name="workflow_ids[]"]:checked').length
    this.countTarget.textContent = `${count} selected`
    this.submitTarget.disabled = count === 0
    this.submitTarget.dataset.turboConfirm = `Delete ${count} selected workflow${count === 1 ? "" : "s"}? This cannot be undone.`
  }
}
