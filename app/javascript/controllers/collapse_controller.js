import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's collapse JS. Structure:
//
//   <div data-controller="collapse">
//     <button data-action="collapse#toggle" aria-expanded="false">Toggle</button>
//     <div data-collapse-target="content" hidden>...</div>
//   </div>
export default class extends Controller {
  static targets = ["content"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.apply()
  }

  toggle(event) {
    event?.preventDefault()
    this.openValue = !this.openValue
    this.apply()
  }

  apply() {
    this.contentTargets.forEach((el) => {
      el.hidden = !this.openValue
    })
    if (this.hasToggleButton) {
      this.toggleButton.setAttribute("aria-expanded", String(this.openValue))
    }
  }

  get toggleButton() {
    return this.element.querySelector("[data-action~='collapse#toggle']")
  }

  get hasToggleButton() {
    return !!this.toggleButton
  }
}
