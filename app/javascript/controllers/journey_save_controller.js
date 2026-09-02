// app/javascript/controllers/journey_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "icon", "label"]
  static values = { saveUrl: String }

  async save() {
    const button = this.hasButtonTarget ? this.buttonTarget : this.element
    button.disabled = true

    try {
      const response = await fetch(this.saveUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) throw new Error("Save failed")

      this.showSaved()
    } catch (error) {
      console.error(error)
      button.disabled = false
    }
  }

  showSaved() {
    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("fa-regular")
      this.iconTarget.classList.add("fa-solid", "saved")
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = "Saved"
    }
  }
}
