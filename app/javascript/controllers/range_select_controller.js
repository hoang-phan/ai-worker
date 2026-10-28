import { Controller } from "@hotwired/stimulus"

// Workflow selection checkboxes (target "box"): Shift-click ticks/unticks the range between the clicked box and the
// closest other ticked box (by row distance), like a file list. Dispatches range-select:changed on any change.
export default class extends Controller {
  static targets = ["box"]

  click(event) {
    const boxes = this.boxTargets
    const index = boxes.indexOf(event.target)
    if (event.shiftKey) {
      const anchor = this.closestChecked(boxes, index)
      if (anchor !== null) {
        const [from, to] = anchor < index ? [anchor, index] : [index, anchor]
        for (let i = from; i <= to; i++) boxes[i].checked = event.target.checked
      }
    }
    this.dispatch("changed")
  }

  toggleAll(event) {
    this.boxTargets.forEach((box) => { box.checked = event.target.checked })
    this.dispatch("changed")
  }

  selectAll() {
    this.setChecked(() => true)
  }

  // Selects only workflows that can log time and have nothing logged yet; clears every other selection.
  selectFresh() {
    this.setChecked((box) => box.dataset.fresh === "true")
  }

  setChecked(predicate) {
    this.boxTargets.forEach((box) => { box.checked = predicate(box) })
    this.dispatch("changed")
  }

  closestChecked(boxes, index) {
    let best = null
    boxes.forEach((box, i) => {
      if (i === index || !box.checked) return
      if (best === null || Math.abs(i - index) < Math.abs(best - index)) best = i
    })
    return best
  }
}
