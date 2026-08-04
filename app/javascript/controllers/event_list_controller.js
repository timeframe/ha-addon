import { Controller } from "@hotwired/stimulus"

// Drives the Events list (mirrors the cloud controller). Delegated listeners so
// it keeps working across full-page reloads. Expected hooks within the element:
//   [data-bulk-row]                 a selectable event row
//   [data-bulk-checkbox]            the row's selection checkbox
//   [data-bulk-select-all]          select/deselect-all button
//   [data-bulk-count]               element(s) showing the selected count
//   [data-bulk-actions]             the bulk action bar (gets .is-active)
//   [data-bulk-hide]                "Hide" bulk button
//   [data-bulk-hide-form]           the sibling hide form
//   [data-bulk-filter]              the text filter input
//   [data-event-search]             per-row lowercase search haystack
//   [data-calendar-id]              per-row calendar id (for the calendar filter)
//   [data-bulk-day-heading]         a day heading (hidden when its rows all hide)
//   [data-event-calendar-select]    the calendar <select>
//   [data-bulk-list]                the row container (holds data-calendar-filter)
//   [data-toggle-hidden]            "show hidden" toggle (value = container id)
export default class extends Controller {
  connect() {
    this.onChange = this.onChange.bind(this)
    this.onClick = this.onClick.bind(this)
    this.onInput = this.onInput.bind(this)

    this.element.addEventListener("change", this.onChange)
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("input", this.onInput)

    this.refreshButtons()
    this.applyRowFilters()
  }

  disconnect() {
    this.element.removeEventListener("change", this.onChange)
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("input", this.onInput)
  }

  get list() {
    return this.element.querySelector("[data-bulk-list]")
  }

  rows() {
    return Array.from(this.element.querySelectorAll("[data-bulk-row]"))
  }

  checkedBoxes() {
    return Array.from(this.element.querySelectorAll("[data-bulk-checkbox]:checked"))
  }

  visibleBoxes() {
    return this.rows()
      .filter((row) => window.getComputedStyle(row).display !== "none")
      .map((row) => row.querySelector("[data-bulk-checkbox]"))
      .filter(Boolean)
  }

  onChange(e) {
    const t = e.target
    if (!t.matches) return
    if (t.matches("[data-bulk-checkbox]")) {
      this.refreshButtons()
    } else if (t.matches("[data-event-calendar-select]")) {
      this.onCalendarSelect(t.value)
    }
  }

  onInput(e) {
    if (e.target.matches?.("[data-bulk-filter]")) this.applyRowFilters()
  }

  onClick(e) {
    const selectAll = e.target.closest("[data-bulk-select-all]")
    if (selectAll && this.element.contains(selectAll)) return this.toggleSelectAll()

    const hide = e.target.closest("[data-bulk-hide]")
    if (hide && this.element.contains(hide)) return this.submitBulk(this.element.querySelector("[data-bulk-hide-form]"))

    const toggle = e.target.closest("[data-toggle-hidden]")
    if (toggle && this.element.contains(toggle)) return this.toggleHidden(toggle)
  }

  toggleSelectAll() {
    const boxes = this.visibleBoxes()
    const allChecked = boxes.length > 0 && boxes.every((b) => b.checked)
    boxes.forEach((b) => { b.checked = !allChecked })
    this.refreshButtons()
  }

  toggleHidden(btn) {
    const container = document.getElementById(btn.getAttribute("data-toggle-hidden"))
    if (!container) return
    const showing = container.classList.toggle("tf-show-hidden")
    const n = btn.getAttribute("data-hidden-count") || ""
    btn.textContent = showing ? "Hide hidden" : `Show ${n} hidden`
  }

  onCalendarSelect(value) {
    const list = this.list
    if (!list) return
    list.dataset.calendarFilter = value.indexOf("cal:") === 0 ? value.slice(4) : ""
    this.applyRowFilters()
  }

  refreshButtons() {
    const n = this.checkedBoxes().length
    this.element.querySelectorAll("[data-bulk-hide]").forEach((b) => { b.disabled = n === 0 })
    this.element.querySelectorAll("[data-bulk-count]").forEach((el) => { el.textContent = n })
    const bar = this.element.querySelector("[data-bulk-actions]")
    if (bar) bar.classList.toggle("is-active", n > 0)
    this.refreshSelectAll()
  }

  refreshSelectAll() {
    const btn = this.element.querySelector("[data-bulk-select-all]")
    if (!btn) return
    const boxes = this.visibleBoxes()
    const allChecked = boxes.length > 0 && boxes.every((b) => b.checked)
    btn.disabled = boxes.length === 0
    const icon = btn.querySelector(".mdi")
    if (icon) icon.className = "mdi " + (allChecked ? "mdi-select-off" : "mdi-select-all")
    const label = btn.querySelector("[data-select-all-label]")
    if (label) label.textContent = allChecked ? "Deselect all" : "Select all"
  }

  applyRowFilters() {
    const input = this.element.querySelector("[data-bulk-filter]")
    const q = input ? input.value.trim().toLowerCase() : ""
    const cal = this.list?.dataset.calendarFilter || ""
    this.rows().forEach((row) => {
      const hay = row.getAttribute("data-event-search") || ""
      const matchesText = !q || hay.indexOf(q) !== -1
      const matchesCal = !cal || row.getAttribute("data-calendar-id") === cal
      if (matchesText && matchesCal) {
        row.style.removeProperty("display")
      } else {
        row.style.setProperty("display", "none", "important")
      }
    })
    this.element.querySelectorAll("[data-bulk-day-heading]").forEach((heading) => {
      let anyVisible = false
      let node = heading.nextElementSibling
      while (node && !node.hasAttribute("data-bulk-day-heading")) {
        if (node.hasAttribute("data-bulk-row") && window.getComputedStyle(node).display !== "none") {
          anyVisible = true
          break
        }
        node = node.nextElementSibling
      }
      heading.style.display = anyVisible ? "" : "none"
    })
    this.refreshSelectAll()
  }

  populate(form) {
    if (!form) return
    form.querySelectorAll("input[data-bulk-id]").forEach((i) => i.remove())
    this.checkedBoxes().forEach((cb) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "calendar_event_ids[]"
      input.value = cb.value
      input.setAttribute("data-bulk-id", "")
      form.appendChild(input)
    })
  }

  submitBulk(form) {
    if (!form || this.checkedBoxes().length === 0) return
    this.populate(form)
    if (form.requestSubmit) form.requestSubmit()
    else form.submit()
  }
}
