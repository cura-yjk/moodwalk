// app/javascript/controllers/journey_save_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "icon", "label"]
  static values = { saveUrl: String, saved: Boolean }

  connect() {
    this.render()
  }

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

      const data = await response.json()
      this.savedValue = data.saved
      this.render()
    } catch (error) {
      console.error(error)
    } finally {
      button.disabled = false
    }
  }

  render() {
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("fa-solid", this.savedValue)
      this.iconTarget.classList.toggle("saved", this.savedValue)
      this.iconTarget.classList.toggle("fa-regular", !this.savedValue)
    }

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = this.savedValue ? "Saved" : "Save"
    }
  }
}
