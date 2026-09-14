import { Controller } from "@hotwired/stimulus"

// Manual location entry, for when automatic detection is blocked, wrong, or
// you simply want a walk somewhere other than where you're standing.
//
// Posts to the same PATCH /location endpoint the geolocation controller uses;
// the server forward-geocodes the text (LocationsController#update_from_query).
export default class extends Controller {
  static targets = ["form", "input", "submit", "error"]

  toggle(event) {
    event.preventDefault()
    this.formTarget.hidden = !this.formTarget.hidden
    if (!this.formTarget.hidden) this.inputTarget.focus()
  }

  async submit(event) {
    event.preventDefault()

    const query = this.inputTarget.value.trim()
    if (!query) return

    this.setBusy(true)
    this.hideError()

    try {
      const response = await fetch("/location", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ query })
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        return this.showError(data.error || "Couldn't find that place. Try a nearby landmark or district.")
      }

      window.location.reload()
    } catch {
      this.showError("Couldn't reach the server. Check your connection and try again.")
    } finally {
      this.setBusy(false)
    }
  }

  setBusy(busy) {
    this.submitTarget.disabled = busy
    this.submitTarget.textContent = busy ? "Looking…" : "Use this place"
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
  }
}
