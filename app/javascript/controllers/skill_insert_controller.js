import { Controller } from "@hotwired/stimulus"

// Inserts "/skillname" at the cursor of the target textarea.
export default class extends Controller {
  static targets = ["input"]

  // keep the textarea's selection when a hint button is pressed
  keepSelection(event) {
    event.preventDefault()
  }

  insert(event) {
    const input = this.inputTarget
    const start = input.selectionStart ?? input.value.length
    const end = input.selectionEnd ?? start
    input.setRangeText(`/${event.currentTarget.dataset.skill}`, start, end, "end")
    input.focus()
  }
}
