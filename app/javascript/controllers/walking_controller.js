import { Controller } from "@hotwired/stimulus"

// How close (in meters) the user needs to be to a waypoint before it counts
// as "arrived" there — GPS accuracy means this can't be 0.
const ARRIVAL_THRESHOLD_METERS = 8

// Average meters per step, used to convert a raw distance into a rough step count.
const STEP_LENGTH_METERS = 0.76

// How long a turn instruction ("Turn left") stays on screen before the app
// moves on to the next leg and resets to the generic "keep going straight" state.
const TURN_FLASH_MS = 1800

// Simulated walking speed (meters/second) used only in dev-mode ?simulate= testing.
const SIMULATION_BASE_SPEED_MPS = 1.4
const SIMULATION_TICK_MS = 500

// Display text for each waypoint's instruction type.
const INSTRUCTION_LABELS = {
  start: "Keep going straight",
  left: "Turn left",
  right: "Turn right",
  end: "You've arrived"
}

// Fixed icon rotation per instruction, rather than a live compass bearing to the
// target -- the arrow only ever shows one of these three positions, never a
// continuously-recalculated angle. Anything besides left/right (start, end,
// missing) falls back to 0 via the `?? 0` at the call site.
const TURN_ANGLES = {
  left: -90,
  right: 90
}

export default class extends Controller {
  static targets = ["arrow", "stepsCount", "instructionText", "nextRow", "nextInstructionText", "cameraButton"]
  static values = { waypoints: Array, currentIndex: { type: Number, default: 0 }, devMode: Boolean, attachPhotoUrl: String }

  connect() {
    this.arrived = false
    this.transitioning = false

    const params = new URLSearchParams(window.location.search)

    // Dev-only shortcut to preview the completed-walk state instantly, without
    // waiting through a real or simulated walk -- handy when you're just
    // iterating on the arrived screen's styling.
    if (this.devModeValue && params.has("arrived")) {
      this.renderArrived()
      return
    }

    // Dev-only shortcut to fake movement along the route instead of physically
    // walking it during testing. Speed multiplier comes from the query param.
    if (this.devModeValue && params.has("simulate")) {
      this.startSimulation(parseFloat(params.get("simulate")) || 6)
      return
    }

    // Bail out early with a clear message on devices/browsers with no
    // geolocation support at all, rather than silently doing nothing.
    if (!("geolocation" in navigator)) {
      this.instructionTextTarget.textContent = "Location not supported on this device"
      return
    }

    // Real-world tracking: fires handlePosition every time the device's
    // location updates, for as long as this controller is connected.
    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.handlePosition(position),
      (error) => this.handleError(error),
      { enableHighAccuracy: true, maximumAge: 2000, timeout: 10000 }
    )
  }

  // Stimulus calls this automatically when the element leaves the page --
  // makes sure we're not still watching location or running timers afterward.
  disconnect() {
    this.stopTracking()
  }

  // Dev-only: fakes a walk along the route's waypoints so the live guidance can be
  // tested without physically moving. Enabled via ?simulate=<speed multiplier>,
  // and gated server-side by devModeValue so it can never activate outside development.
  startSimulation(speedMultiplier) {
    this.simulationDistance = 0

    // On a fixed interval, calculate where a "virtual walker" would be by now
    // and feed that position through the exact same handlePosition logic
    // real GPS updates use -- so the guidance behaves identically either way.
    this.simulationTimer = setInterval(() => {
      const point = this.pointAtDistance(this.simulationDistance)
      if (!point) {
        // Ran past the end of the route -- stop simulating.
        clearInterval(this.simulationTimer)
        return
      }
      this.handlePosition({ coords: { latitude: point.lat, longitude: point.lng } })
      this.simulationDistance += SIMULATION_BASE_SPEED_MPS * speedMultiplier * (SIMULATION_TICK_MS / 1000)
    }, SIMULATION_TICK_MS)

    this.showSimulationBadge(speedMultiplier)
  }

  // walks the straight-line legs between waypoints and returns the lat/lng at
  // `distance` meters along that path, or null once past the end.
  pointAtDistance(distance) {
    const path = this.waypointsValue
    let remaining = distance

    // Walk leg by leg (waypoint to waypoint) subtracting each leg's length
    // from `remaining` until we find the leg the target distance falls within.
    for (let i = 0; i < path.length - 1; i++) {
      const legDistance = this.haversineMeters(path[i], path[i + 1])
      if (remaining <= legDistance) {
        // `t` is how far along this specific leg (0 = start, 1 = end) --
        // used to linearly interpolate the exact lat/lng along the way.
        const t = legDistance === 0 ? 0 : remaining / legDistance
        return {
          lat: path[i].lat + ((path[i + 1].lat - path[i].lat) * t),
          lng: path[i].lng + ((path[i + 1].lng - path[i].lng) * t)
        }
      }
      remaining -= legDistance
    }

    // Distance requested is past the end of the entire route.
    return null
  }

  // Visual-only indicator so it's obvious on screen that you're looking at
  // a simulated walk, not a real GPS-tracked one.
  showSimulationBadge(speedMultiplier) {
    const badge = document.createElement("div")
    badge.textContent = `SIMULATING WALK (${speedMultiplier}x speed)`
    badge.style.cssText = "position:fixed;top:0;left:0;right:0;z-index:9999;background:#e67e22;color:#fff;text-align:center;font:12px/1.8 sans-serif;letter-spacing:.05em;"
    document.body.prepend(badge)
  }

  // Cleans up anything that would otherwise keep running after the walk
  // screen closes -- geolocation watcher, simulation interval, pending
  // turn-flash timeout.
  stopTracking() {
    if (this.watchId) navigator.geolocation.clearWatch(this.watchId)
    if (this.simulationTimer) clearInterval(this.simulationTimer)
    if (this.transitionTimeout) clearTimeout(this.transitionTimeout)
  }

  // Mid-leg, the guidance is deliberately generic ("keep going straight") no
  // matter what the upcoming turn is -- the turn itself is only previewed in the
  // THEN row, and gets its moment on the main arrow in handleArrival below.
  handlePosition(position) {
    // Ignore updates while we've already arrived, or while mid-transition
    // between one waypoint and the next (avoids double-triggering arrival).
    if (this.arrived || this.transitioning) return

    const current = { lat: position.coords.latitude, lng: position.coords.longitude }
    const target = this.waypointsValue[this.currentIndexValue]
    if (!target) return

    const distance = this.haversineMeters(current, target)

    // Close enough to the current target waypoint -- treat this as arrival
    // there, rather than continuing to show "keep going straight."
    if (distance < ARRIVAL_THRESHOLD_METERS) {
      this.handleArrival(target)
      return
    }

    // Still en route: reset the arrow to neutral, update the live step
    // count based on remaining distance, and show the generic instruction.
    this.arrowTarget.style.transform = "rotate(0deg)"
    this.stepsCountTarget.textContent = Math.round(distance / STEP_LENGTH_METERS)
    this.instructionTextTarget.textContent = "Keep going straight"

    this.renderNextTurn(target)
  }

  // Shows the turn that's actually happening right now, briefly, then resets to
  // the generic "keep going straight" state for the next leg. The final waypoint
  // ("end") has no next leg, so it goes straight to the arrived state instead.
  handleArrival(target) {
    if (target.instruction === "end") {
      this.renderArrived()
      return
    }

    // Briefly show the turn itself on the main arrow (rotated left/right),
    // hide the "THEN" preview row since we're now doing that turn, then
    // after TURN_FLASH_MS advance to the next waypoint and resume normal
    // "keep going straight" guidance via the next handlePosition call.
    this.transitioning = true
    this.arrowTarget.style.transform = `rotate(${TURN_ANGLES[target.instruction] ?? 0}deg)`
    this.stepsCountTarget.textContent = "0"
    this.instructionTextTarget.textContent = INSTRUCTION_LABELS[target.instruction] || "Turn"
    this.nextRowTarget.classList.add("next-instruction-hidden")

    this.transitionTimeout = setTimeout(() => {
      this.currentIndexValue += 1
      this.transitioning = false
    }, TURN_FLASH_MS)
  }

  // Previews the maneuver at the point we're currently walking toward -- i.e.
  // the next turn that's actually coming up.
  renderNextTurn(target) {
    this.nextRowTarget.classList.remove("next-instruction-hidden")
    this.nextInstructionTextTarget.textContent = INSTRUCTION_LABELS[target.instruction] || "Continue"
  }

  // Final state once the last waypoint is reached: swaps the arrow icon for
  // a checkmark, zeroes out the step count, and stops all tracking/timers
  // since there's nothing left to navigate toward.
  renderArrived() {
    this.arrived = true
    this.stopTracking()

    this.arrowTarget.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
    this.arrowTarget.style.transform = "rotate(0deg)"
    this.stepsCountTarget.textContent = "0"
    this.instructionTextTarget.textContent = "You've arrived!"
    this.nextRowTarget.classList.add("next-instruction-hidden")
  }

  // Now actually uploads the captured photo to Cloudinary via Active Storage,
  // instead of just hiding the button and discarding the file.
  photoTaken(event) {
    const file = event.target.files[0]
    console.log("hi", file)
    if (!file) return

    const formData = new FormData()
    formData.append("walk[photo]", file)

    const csrfToken = document.querySelector('meta[name="csrf-token"]').content

    fetch(this.attachPhotoUrlValue, {
      method: "PATCH",
      headers: { "X-CSRF-Token": csrfToken },
      body: formData
    })
      .then((response) => {
        if (response.ok) {
          this.cameraButtonTarget.classList.add("d-none")
        } else {
          alert("Photo upload failed — try again.")
        }
      })
      .catch(() => alert("Photo upload failed — check your connection."))
  }

  // Geolocation failure handler -- distinguishes "user said no" (permission
  // denied) from other transient issues (still waiting for a GPS fix, etc.)
  // so the on-screen message tells the user what to actually do about it.
  handleError(error) {
    this.instructionTextTarget.textContent = error.code === error.PERMISSION_DENIED
      ? "Enable location access to continue"
      : "Waiting for a location signal…"
  }

  // Standard haversine formula: great-circle distance in meters between two
  // lat/lng points, accounting for the Earth's curvature (a flat-plane
  // distance calculation would be noticeably wrong at this scale).
  haversineMeters(a, b) {
    const R = 6371000 // Earth's radius in meters
    const dLat = (b.lat - a.lat) * Math.PI / 180
    const dLng = (b.lng - a.lng) * Math.PI / 180
    const lat1 = a.lat * Math.PI / 180
    const lat2 = b.lat * Math.PI / 180
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
    return 2 * R * Math.asin(Math.sqrt(h))
  }
}
