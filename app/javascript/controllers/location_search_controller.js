import { Controller } from "@hotwired/stimulus"

// Drives the "Change" link on the homepage: toggles a small inline search
// field, and on submit sends the typed place name to LocationsController
// (which geocodes it server-side) rather than trusting free-text
// coordinates from the client.
export default class extends Controller {
  static targets = ["form", "input"]

  toggle(event) {
    event.preventDefault()
    this.formTarget.classList.toggle("d-none")
    if (!this.formTarget.classList.contains("d-none")) this.inputTarget.focus()
  }

  async submit(event) {
    event.preventDefault()

    const query = this.inputTarget.value.trim()
    if (!query) return

    this.inputTarget.setCustomValidity("")

    const response = await fetch("/location", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ query })
    })

    if (response.ok) {
      window.location.reload()
      return
    }

    // Keep the field open so they can try a different search, rather than
    // a disruptive alert.
    const body = await response.json().catch(() => ({}))
    this.inputTarget.setCustomValidity(body.error || "Couldn't find that place")
    this.inputTarget.reportValidity()
  }
}
