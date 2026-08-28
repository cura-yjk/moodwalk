import { Controller } from "@hotwired/stimulus"

const SYNCED_KEY = "moodwalk:location-synced"

export default class extends Controller {
  connect() {
    if (this.alreadySynced()) return
    if (!("geolocation" in navigator)) return

    navigator.geolocation.getCurrentPosition(
      (position) => this.sync(position.coords),
      () => {},
      { maximumAge: 5 * 60 * 1000 }
    )
  }

  async sync(coords) {
    // Mark synced before the request resolves so a slow/failed request
    // can't cause connect() to retry after the reload below.
    this.markSynced()

    const response = await fetch("/location", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ latitude: coords.latitude, longitude: coords.longitude })
    })

    if (response.ok) window.location.reload()
  }

  alreadySynced() {
    try {
      return window.sessionStorage.getItem(SYNCED_KEY) === "true"
    } catch {
      return false
    }
  }

  markSynced() {
    try {
      window.sessionStorage.setItem(SYNCED_KEY, "true")
    } catch {
    }
  }
}
