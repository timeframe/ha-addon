import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's navbar collapse toggler. Wrap the toggle and the
// collapsible menu:
//
//   <nav data-controller="navbar">
//     <button data-action="navbar#toggle" aria-expanded="false">...</button>
//     <div data-navbar-target="menu" class="hidden md:flex">...</div>
//   </nav>
//
// Toggles the `hidden` utility on the menu at mobile widths.
export default class extends Controller {
  static targets = ["menu", "button"]

  toggle(event) {
    event?.preventDefault()
    const collapsed = this.menuTarget.classList.toggle("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", String(!collapsed))
  }
}
