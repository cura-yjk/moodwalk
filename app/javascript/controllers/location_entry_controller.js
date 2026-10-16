import { Controller } from "@hotwired/stimulus"

// Every search is a Mapbox call or two (LocationsController#suggest falls back
// to a global search). At 250ms after each keystroke, one session typing and
// correcting "meiji jingumae" made 30 in 28 seconds.
const DEBOUNCE_MS = 500
// Two Latin letters ("ma", "ju") match half of Tokyo, but two characters is a
// whole place name in Japanese (渋谷, 目黒) - so the shorter minimum applies
// to anything that isn't plain ASCII.
const MIN_QUERY_LENGTH = 3
const MIN_QUERY_LENGTH_NON_ASCII = 2

// Choosing where a walk starts from.
//
// Deliberately never commits to a guess: Mapbox answers almost any input, so
// typing shows named suggestions and you pick one. The two faster paths --
// re-detecting where you are, and the places you started from recently --
// come first, because this is used on a phone, outdoors, one-handed.
export default class extends Controller {
  static targets = ["panel", "input", "results", "error", "detect"]

  toggle(event) {
    event.preventDefault()
    this.panelTarget.hidden = !this.panelTarget.hidden
    if (!this.panelTarget.hidden) this.inputTarget.focus()
  }

  // --- typeahead -----------------------------------------------------------

  // Chinese and Japanese are mostly typed through an input method: the field
  // holds pinyin or romaji ("beij") until the word is converted (北京).
  // Searching those halfway letters costs a Mapbox call for nothing, so wait
  // for compositionend, which the field also routes here.
  search(event) {
    if (event?.isComposing) return

    clearTimeout(this.timer)
    const query = this.inputTarget.value.trim()
    const minimum = /^[\x00-\x7F]*$/.test(query) ? MIN_QUERY_LENGTH : MIN_QUERY_LENGTH_NON_ASCII

    if (query.length < minimum) return this.clearResults()

    // Typing back to something already searched - deleting a letter, fixing a
    // typo - costs nothing. Kept for the page's life: choosing a place reloads
    // it, which is also when "nearby" changes.
    const cached = this.suggestionCache?.get(this.cacheKey(query))
    if (cached) return this.renderResults(cached)

    this.timer = setTimeout(() => this.fetchSuggestions(query), DEBOUNCE_MS)
  }

  cacheKey(query) {
    return query.toLowerCase()
  }

  async fetchSuggestions(query) {
    this.hideError()

    try {
      const response = await fetch(`/location/autocomplete?query=${encodeURIComponent(query)}`, {
        headers: { Accept: "application/json" }
      })
      if (!response.ok) return this.showError("Couldn't search for places just now.")

      const { results } = await response.json()
      this.suggestionCache ??= new Map()
      this.suggestionCache.set(this.cacheKey(query), results || [])

      // An answer to an older query, arriving after the field has moved on -
      // more likely now that cached queries render straight away.
      if (this.cacheKey(this.inputTarget.value.trim()) !== this.cacheKey(query)) return

      this.renderResults(results || [])
    } catch {
      this.showError("Couldn't reach the server. Check your connection.")
    }
  }

  renderResults(results) {
    this.activeIndex = -1

    if (results.length === 0) {
      // Not an option: there is nothing here to select or arrow onto.
      this.resultsTarget.innerHTML =
        '<li class="location-result-empty">No places found. Try a district or nearby landmark.</li>'
      return this.openResults()
    }

    // The district/region line is the point of this list: it is what makes a
    // wrong match obvious before it is applied, rather than after.
    this.resultsTarget.innerHTML = results
      .map(
        (r, i) => `
        <li id="location-result-${i}" role="option" aria-selected="false" class="location-result"
            data-action="click->location-entry#choose mousemove->location-entry#hover"
            data-index="${i}" data-lat="${r.lat}" data-lng="${r.lng}" data-name="${this.escape(r.name)}">
          <span class="location-result-name">${this.escape(r.name)}</span>
          <span class="location-result-context">${this.escape(r.place_formatted || "")}</span>
        </li>`
      )
      .join("")
    this.openResults()
  }

  choose(event) {
    const { lat, lng, name } = event.currentTarget.dataset
    this.commit({ latitude: Number(lat), longitude: Number(lng), name, source: "manual" })
  }

  // --- keyboard ------------------------------------------------------------

  // Arrow keys move a highlight rather than focus. Focus stays in the input so
  // you can keep typing to narrow the list, which is why the active option is
  // announced through aria-activedescendant instead.
  navigate(event) {
    // Enter and the arrow keys belong to the input method while it's
    // converting - Enter there confirms the characters, not a result. 229 is
    // what some browsers report instead of isComposing.
    if (event.isComposing || event.keyCode === 229) return
    if (event.key === "Escape") return this.clearResults()

    const options = this.options()
    if (options.length === 0) return

    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.highlight((this.activeIndex + 1) % options.length)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.highlight((this.activeIndex - 1 + options.length) % options.length)
    } else if (event.key === "Enter" && this.activeIndex >= 0) {
      // Only when something is highlighted -- otherwise Enter should do
      // nothing rather than guess at the first result.
      event.preventDefault()
      options[this.activeIndex].click()
    }
  }

  hover(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (index !== this.activeIndex) this.highlight(index)
  }

  highlight(index) {
    const options = this.options()
    this.activeIndex = index

    options.forEach((option, i) => {
      const active = i === index
      option.classList.toggle("is-active", active)
      option.setAttribute("aria-selected", active ? "true" : "false")
    })

    const active = options[index]
    if (!active) return

    this.inputTarget.setAttribute("aria-activedescendant", active.id)
    active.scrollIntoView({ block: "nearest" })
  }

  options() {
    return Array.from(this.resultsTarget.querySelectorAll('[role="option"]'))
  }

  openResults() {
    this.resultsTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
  }

  // --- one-tap paths -------------------------------------------------------

  useRecent(event) {
    const { lat, lng, name } = event.currentTarget.dataset
    this.commit({ latitude: Number(lat), longitude: Number(lng), name, source: "manual" })
  }

  // Asks the browser again, ignoring the "moved far enough?" check that
  // governs automatic syncing -- this is an explicit request. It is also the
  // way back if the permission prompt was dismissed earlier.
  detect(event) {
    event.preventDefault()

    if (!("geolocation" in navigator)) return this.showError("This browser can't detect your location.")

    this.detectTarget.disabled = true
    this.detectTarget.textContent = "Locating…"

    navigator.geolocation.getCurrentPosition(
      // "detect" rather than no source: this is an explicit request, so it is
      // allowed to move a pinned location and hand tracking back to the app.
      ({ coords }) => this.commit({ latitude: coords.latitude, longitude: coords.longitude, source: "detect" }),
      (error) => {
        this.resetDetect()
        this.showError(
          error.code === error.PERMISSION_DENIED
            ? "Location is blocked for this site. Allow it in your browser settings, or search for a place instead."
            : "Couldn't get a location fix. Try searching for a place instead."
        )
      },
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60 * 1000 }
    )
  }

  resetDetect() {
    if (!this.hasDetectTarget) return
    this.detectTarget.disabled = false
    this.detectTarget.textContent = "Use my current location"
  }

  // --- shared --------------------------------------------------------------

  async commit(body) {
    this.hideError()

    try {
      const response = await fetch("/location", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify(body)
      })

      if (!response.ok) {
        const data = await response.json().catch(() => ({}))
        this.resetDetect()
        return this.showError(data.error || "Couldn't set that location.")
      }

      window.location.reload()
    } catch {
      this.resetDetect()
      this.showError("Couldn't reach the server. Check your connection.")
    }
  }

  clearResults() {
    this.activeIndex = -1
    this.resultsTarget.innerHTML = ""
    this.resultsTarget.hidden = true
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
  }

  hideError() {
    this.errorTarget.hidden = true
  }

  escape(text) {
    const el = document.createElement("div")
    el.textContent = text
    return el.innerHTML
  }
}
