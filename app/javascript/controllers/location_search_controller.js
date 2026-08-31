import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 250
const MIN_QUERY_LENGTH = 2

export default class extends Controller {
  static targets = ["form", "input", "suggestions"]

  toggle(event) {
    event.preventDefault()
    this.formTarget.classList.toggle("d-none")
    if (!this.formTarget.classList.contains("d-none")) this.inputTarget.focus()
  }

  type() {
    clearTimeout(this.debounceTimer)
    this.abortController?.abort()

    const query = this.inputTarget.value.trim()
    if (query.length < MIN_QUERY_LENGTH) return this.close()

    this.debounceTimer = setTimeout(() => this.fetchSuggestions(query), DEBOUNCE_MS)
  }

  async fetchSuggestions(query) {
    this.abortController = new AbortController()

    let response
    try {
      response = await fetch(`/location/autocomplete?query=${encodeURIComponent(query)}`, {
        signal: this.abortController.signal
      })
    } catch {
      return // aborted by a newer keystroke
    }

    if (!response.ok) return this.close()

    const { results } = await response.json()
    this.renderSuggestions(results || [])
  }

  renderSuggestions(results) {
    this.suggestionsTarget.replaceChildren()

    if (results.length === 0) return this.close()

    for (const result of results) {
      const li = document.createElement("li")
      li.className = "location-suggestion"
      li.textContent = result.place_formatted || result.name
      li.tabIndex = 0
      li.dataset.lat = result.lat
      li.dataset.lng = result.lng
      li.dataset.name = result.name
      li.dataset.action = "mousedown->location-search#select"
      this.suggestionsTarget.appendChild(li)
    }

    this.suggestionsTarget.classList.remove("d-none")
  }

  async select(event) {
    event.preventDefault() // fires before the input's blur, so focus/close don't race it

    const { lat, lng, name } = event.currentTarget.dataset
    this.close()
    this.inputTarget.value = name

    const response = await fetch("/location", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ latitude: lat, longitude: lng, name })
    })

    if (response.ok) window.location.reload()
  }

  async submit(event) {
    event.preventDefault()
    this.close()

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

  close() {
    this.suggestionsTarget.classList.add("d-none")
    this.suggestionsTarget.replaceChildren()
  }
}
