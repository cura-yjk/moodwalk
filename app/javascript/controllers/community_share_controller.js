import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]
  static values = { shareUrl: String }

  async share() {
    const button = this.hasButtonTarget ? this.buttonTarget : this.element
    button.disabled = true

    try {
      const response = await fetch(this.shareUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
        }
      })

      if (!response.ok) throw new Error("Share failed")
    } catch (error) {
      console.error(error)
      button.disabled = false
    }
  }
}
