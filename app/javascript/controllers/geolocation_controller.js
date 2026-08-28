import { Controller } from "@hotwired/stimulus"

// On the homepage, silently requests the browser's current location and
// syncs it to the server (current_user.current_latitude/current_longitude)
// so PagesController#home can find/generate nearby journeys. Runs at most
// once per browser session -- if permission is denied or the browser
// doesn't support geolocation, it just does nothing and the homepage falls
// back to whatever location (or lack of one) is already on file. No
// prompts, no error messages -- getting a location is a nice-to-have here,
// not something to make a user deal with.
const SYNCED_KEY = "moodwalk:location-synced"

export default class extends Controller {
  connect() {
    if (this.alreadySynced()) return
    if (!("geolocation" in navigator)) return

    navigator.geolocation.getCurrentPosition(
      (position) => this.sync(position.coords),
      () => {}, // permission denied / unavailable -- nothing to do
      { maximumAge: 5 * 60 * 1000 } // reuse a recent fix rather than re-prompting every load
    )
  }

  async sync(coords) {
    // Mark synced before the network call resolves, and regardless of
    // outcome -- so a slow or failed request can't cause connect() to
    // fire this again after the page reloads below.
    this.markSynced()

    const response = await fetch("/location", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ latitude: coords.latitude, longitude: coords.longitude })
    })

    // Reload once so PagesController#home re-runs with the now-known
    // location and can show/generate nearby journeys.
    if (response.ok) window.location.reload()
  }

  alreadySynced() {
    try {
      return window.sessionStorage.getItem(SYNCED_KEY) === "true"
    } catch {
      return false // storage disabled -- worst case, it re-syncs every load
    }
  }

  markSynced() {
    try {
      window.sessionStorage.setItem(SYNCED_KEY, "true")
    } catch {
      // Private browsing / storage disabled -- fine, this session just
      // won't remember it already synced.
    }
  }
}
