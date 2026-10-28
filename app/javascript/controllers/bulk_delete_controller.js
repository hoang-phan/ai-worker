import { Controller } from "@hotwired/stimulus"

// Shows the number of ticked workflows, enables "Delete selected" and sets its confirm dialog text.
// "Log time" buttons stay disabled while any ticked workflow cannot log time (data-log-time="false").
export default class extends Controller {
  static targets = ["count", "submit", "logTime"]

  update() {
    const checked = document.querySelectorAll('input[form="workflow-selection-form"][name="workflow_ids[]"]:checked')
    const count = checked.length
    const canLogTime = count > 0 && Array.from(checked).every((box) => box.dataset.logTime === "true")
    this.countTarget.textContent = `${count} selected`
    this.submitTarget.disabled = count === 0
    this.submitTarget.dataset.turboConfirm = `Delete ${count} selected workflow${count === 1 ? "" : "s"}? This cannot be undone.`
    this.logTimeTargets.forEach((button) => {
      button.disabled = !canLogTime
      button.title = count > 0 && !canLogTime ? "Selection includes a workflow that cannot log time" : ""
    })
  }
}
