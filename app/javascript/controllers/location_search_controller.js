import { Controller } from "@hotwired/stimulus"

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

    const body = await response.json().catch(() => ({}))
    this.inputTarget.setCustomValidity(body.error || "Couldn't find that place")
    this.inputTarget.reportValidity()
  }
}
