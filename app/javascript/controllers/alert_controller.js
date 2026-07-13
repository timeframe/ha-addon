import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's dismissible-alert JS. Put on a flash/alert element with
// a close button:
//
//   <div data-controller="alert" role="alert">
//     ...
//     <button data-action="alert#dismiss" aria-label="Close">&times;</button>
//   </div>
export default class extends Controller {
  dismiss(event) {
    event?.preventDefault()
    this.element.remove()
  }
}
