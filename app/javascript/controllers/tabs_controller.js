import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's tab JS. Structure:
//
//   <div data-controller="tabs" data-tabs-active-class="tab-active">
//     <button data-tabs-target="tab" data-action="tabs#select" data-panel="preview">Preview</button>
//     <button data-tabs-target="tab" data-action="tabs#select" data-panel="screenshot">Screenshot</button>
//     <div data-tabs-target="panel" data-panel="preview">...</div>
//     <div data-tabs-target="panel" data-panel="screenshot" hidden>...</div>
//   </div>
//
// The first tab (or one marked data-tabs-default) is shown on connect.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static classes = ["active"]

  connect() {
    const initial =
      this.tabTargets.find((t) => t.dataset.tabsDefault !== undefined) || this.tabTargets[0]
    if (initial) this.activate(initial.dataset.panel)
  }

  select(event) {
    event.preventDefault()
    this.activate(event.currentTarget.dataset.panel)
  }

  activate(panelName) {
    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.panel !== panelName
    })
    this.tabTargets.forEach((tab) => {
      const on = tab.dataset.panel === panelName
      tab.setAttribute("aria-selected", String(on))
      if (this.hasActiveClass) {
        this.activeClasses.forEach((c) => tab.classList.toggle(c, on))
      }
    })
  }
}
