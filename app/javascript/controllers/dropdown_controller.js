import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's dropdown JS (Popper). Wrap the toggle and menu:
//
//   <div data-controller="dropdown" data-action="keydown.esc->dropdown#hide">
//     <button data-action="dropdown#toggle" aria-expanded="false">Menu</button>
//     <div data-dropdown-target="menu" class="hidden">...</div>
//   </div>
//
// Toggle the `hidden` utility class on the menu; close on outside click / Esc.
export default class extends Controller {
  static targets = ["menu", "button"]

  connect() {
    this.hideOnOutsideClick = this.hideOnOutsideClick.bind(this)
    this.hideOnEscape = this.hideOnEscape.bind(this)
  }

  toggle(event) {
    event?.preventDefault()
    this.menuTarget.classList.contains("hidden") ? this.show() : this.hide()
  }

  show() {
    this.menuTarget.classList.remove("hidden")
    this.setExpanded(true)
    document.addEventListener("click", this.hideOnOutsideClick)
    document.addEventListener("keydown", this.hideOnEscape)
  }

  hide() {
    this.menuTarget.classList.add("hidden")
    this.setExpanded(false)
    document.removeEventListener("click", this.hideOnOutsideClick)
    document.removeEventListener("keydown", this.hideOnEscape)
  }

  hideOnOutsideClick(event) {
    if (!this.element.contains(event.target)) this.hide()
  }

  hideOnEscape(event) {
    if (event.key === "Escape") this.hide()
  }

  setExpanded(value) {
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", String(value))
  }

  disconnect() {
    document.removeEventListener("click", this.hideOnOutsideClick)
    document.removeEventListener("keydown", this.hideOnEscape)
  }
}
