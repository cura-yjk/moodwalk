import { Controller } from "@hotwired/stimulus"

// Shows a journey's highlights, and upgrades them when the written ones land.
//
// The request used to generate them inline, so this list sat empty for about
// twelve seconds on a journey nobody had opened before. Now the server answers
// immediately with highlights derived from the route itself and writes the
// better ones in the background, so there is always something on screen.
const RETRY_MS = 3000
const MAX_RETRIES = 6

export default class extends Controller {
  static targets = ["list"]
  static values = { url: String }

  connect() {
    this.attempts = 0
    this.load()
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  async load({ polling = false } = {}) {
    try {
      const url = polling ? `${this.urlValue}?poll=1` : this.urlValue
      const response = await fetch(url, { headers: { Accept: "application/json" } })

      if (!response.ok) throw new Error("Failed to load highlights")

      const data = await response.json()
      this.render(data.highlights)

      if (data.pending) this.checkAgain()
    } catch (error) {
      // The fallback list is already on screen, so a failed check is not worth
      // showing anyone. Stop asking.
      console.error(error)
    }
  }

  // Asks again while the written highlights are still being produced, then
  // gives up: the ones already on screen are true, just plainer.
  checkAgain() {
    if (this.attempts >= MAX_RETRIES) return

    this.attempts += 1
    this.timeout = setTimeout(() => this.load({ polling: true }), RETRY_MS)
  }

  render(highlights) {
    this.listTarget.replaceChildren(...highlights.map((highlight) => this.item(highlight)))
  }

  // Built as nodes rather than an HTML string: this text comes back from the
  // model, and innerHTML would run whatever markup it happened to produce.
  item({ icon, text }) {
    const li = document.createElement("li")

    li.className = "mb-1 fs-5"
    li.textContent = `${icon} ${text}`

    return li
  }
}
