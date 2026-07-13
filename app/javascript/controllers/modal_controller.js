import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap's modal JS with a native <dialog>. Wrap a trigger and the
// dialog in one controller scope:
//
//   <div data-controller="modal">
//     <button data-action="modal#open">Edit</button>
//     <dialog data-modal-target="dialog" data-action="click->modal#backdropClose">
//       <button data-action="modal#close">Close</button>
//       ...
//     </dialog>
//   </div>
//
// Native <dialog> renders its own top-layer backdrop, so there is no orphaned
// `.modal-backdrop` to clean up after Turbo Frame renders.
export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    event?.preventDefault()
    if (this.hasDialogTarget && !this.dialogTarget.open) {
      this.dialogTarget.showModal()
      this.dispatch("open", { target: this.dialogTarget })
    }
  }

  close(event) {
    event?.preventDefault()
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }

  // Close when the click lands on the dialog element itself (its backdrop),
  // not on the inner content.
  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.dialogTarget.close()
    }
  }

  // If the dialog is removed (e.g. Turbo Frame swap) while open, drop it so the
  // top-layer backdrop can't linger.
  disconnect() {
    if (this.hasDialogTarget && this.dialogTarget.open) {
      this.dialogTarget.close()
    }
  }
}
