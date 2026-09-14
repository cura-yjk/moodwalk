import { Controller } from "@hotwired/stimulus"

// How far you have to have moved before the stored location is worth
// rewriting. Well above normal GPS jitter, so a stationary device doesn't
// bounce across the threshold and reload the page repeatedly.
const MIN_MOVE_METERS = 150

// Floor between two syncs, whatever the coordinates say. A second guard
// against reload loops if a device reports wildly inconsistent fixes.
const MIN_SYNC_INTERVAL_MS = 60 * 1000
const LAST_SYNC_KEY = "moodwalk:location-synced-at"

export default class extends Controller {
  static targets = ["status"]
  static values = { lat: Number, lng: Number }

  connect() {
    if (!("geolocation" in navigator)) return this.showStatus("This browser can't detect your location.")
    if (this.syncedRecently()) return

    navigator.geolocation.getCurrentPosition(
      (position) => this.maybeSync(position.coords),
      (error) => this.reportError(error),
      // A fresh fix matters more than a fast one here: this runs once on load,
      // and a cached position can be minutes old and hundreds of metres out.
      { enableHighAccuracy: true, timeout: 10000, maximumAge: 60 * 1000 }
    )
  }

  // Only write when the fix actually differs from what the server already has.
  // The previous version synced once per browser session instead, so moving
  // anywhere never updated your location until you closed the tab.
  maybeSync(coords) {
    if (this.hasStoredLocation() && this.metersFromStored(coords) < MIN_MOVE_METERS) return

    this.sync(coords)
  }

  async sync(coords) {
    try {
      const response = await fetch("/location", {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ latitude: coords.latitude, longitude: coords.longitude })
      })

      if (!response.ok) return this.showStatus("Couldn't save your location just now.")

      // Marked only after the request succeeds. Marking it up front meant one
      // failed request left you stuck on a stale location for the whole session.
      this.markSynced()
      window.location.reload()
    } catch {
      this.showStatus("Couldn't reach the server to save your location.")
    }
  }

  reportError(error) {
    // Previously swallowed, so a blocked permission prompt looked identical to
    // everything working.
    if (error.code === error.PERMISSION_DENIED) {
      this.showStatus("Location is blocked for this site. Allow it in your browser, or set a location below.")
    } else if (error.code === error.TIMEOUT) {
      this.showStatus("Couldn't get a location fix in time. You can set one below.")
    } else {
      this.showStatus("Couldn't detect your location. You can set one below.")
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
  }

  hasStoredLocation() {
    return this.hasLatValue && this.hasLngValue && this.latValue !== 0 && this.lngValue !== 0
  }

  // Equirectangular approximation -- plenty at this scale, and avoids pulling
  // in the full haversine for a threshold check.
  metersFromStored(coords) {
    const toRad = Math.PI / 180
    const dLat = (coords.latitude - this.latValue) * toRad
    const dLng = (coords.longitude - this.lngValue) * toRad * Math.cos(this.latValue * toRad)

    return Math.sqrt(dLat * dLat + dLng * dLng) * 6378137
  }

  syncedRecently() {
    try {
      const last = Number(window.sessionStorage.getItem(LAST_SYNC_KEY))
      return Boolean(last) && Date.now() - last < MIN_SYNC_INTERVAL_MS
    } catch {
      return false
    }
  }

  markSynced() {
    try {
      window.sessionStorage.setItem(LAST_SYNC_KEY, String(Date.now()))
    } catch {
      // Private browsing with storage blocked: the distance check above still
      // prevents redundant writes, so losing this guard is not fatal.
    }
  }
}
