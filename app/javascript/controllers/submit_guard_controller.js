import { Controller } from "@hotwired/stimulus"

// Disables the submit button until every guarded field has a non-empty value.
//
//   <form data-controller="submit-guard">
//     <input data-submit-guard-target="field" data-action="input->submit-guard#refresh">
//     <button data-submit-guard-target="button" type="submit">Send</button>
//   </form>
export default class extends Controller {
  static targets = ["field", "button"]

  connect() {
    this.refresh()
  }

  refresh() {
    const incomplete = this.fieldTargets.some((field) => field.value.trim() === "")
    this.buttonTargets.forEach((button) => {
      button.disabled = incomplete
    })
  }
}
