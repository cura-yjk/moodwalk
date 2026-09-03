// app/javascript/controllers/journey_highlights_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list"]
  static values = { url: String }

  connect() {
    this.load()
  }

  async load() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { "Accept": "application/json" }
      })

      if (!response.ok) throw new Error("Failed to load highlights")

      const data = await response.json()
      this.render(data.highlights)
    } catch (error) {
      console.error(error)
    }
  }

  render(highlights) {
    this.listTarget.innerHTML = highlights
      .map(h => `<li class="mb-1 fs-5">${h.icon} ${h.text}</li>`)
      .join("")
  }
}
