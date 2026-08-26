// app/javascript/controllers/walking_controller.js
import { Controller } from "@hotwired/stimulus"

const ARRIVAL_THRESHOLD_METERS = 8
const STEP_LENGTH_METERS = 0.76
const TURN_FLASH_MS = 1800 // how long the turn instruction shows before resetting to "straight"
const SIMULATION_BASE_SPEED_MPS = 1.4 // average walking pace
const SIMULATION_TICK_MS = 500

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
  static values = { waypoints: Array, currentIndex: { type: Number, default: 0 }, devMode: Boolean }

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

    if (this.devModeValue && params.has("simulate")) {
      this.startSimulation(parseFloat(params.get("simulate")) || 6)
      return
    }

    if (!("geolocation" in navigator)) {
      this.instructionTextTarget.textContent = "Location not supported on this device"
      return
    }

    this.watchId = navigator.geolocation.watchPosition(
      (position) => this.handlePosition(position),
      (error) => this.handleError(error),
      { enableHighAccuracy: true, maximumAge: 2000, timeout: 10000 }
    )
  }

  disconnect() {
    this.stopTracking()
  }

  // Dev-only: fakes a walk along the route's waypoints so the live guidance can be
  // tested without physically moving. Enabled via ?simulate=<speed multiplier>,
  // and gated server-side by devModeValue so it can never activate outside development.
  startSimulation(speedMultiplier) {
    this.simulationDistance = 0
    this.simulationTimer = setInterval(() => {
      const point = this.pointAtDistance(this.simulationDistance)
      if (!point) {
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

    for (let i = 0; i < path.length - 1; i++) {
      const legDistance = this.haversineMeters(path[i], path[i + 1])
      if (remaining <= legDistance) {
        const t = legDistance === 0 ? 0 : remaining / legDistance
        return {
          lat: path[i].lat + ((path[i + 1].lat - path[i].lat) * t),
          lng: path[i].lng + ((path[i + 1].lng - path[i].lng) * t)
        }
      }
      remaining -= legDistance
    }

    return null
  }

  showSimulationBadge(speedMultiplier) {
    const badge = document.createElement("div")
    badge.textContent = `SIMULATING WALK (${speedMultiplier}x speed)`
    badge.style.cssText = "position:fixed;top:0;left:0;right:0;z-index:9999;background:#e67e22;color:#fff;text-align:center;font:12px/1.8 sans-serif;letter-spacing:.05em;"
    document.body.prepend(badge)
  }

  stopTracking() {
    if (this.watchId) navigator.geolocation.clearWatch(this.watchId)
    if (this.simulationTimer) clearInterval(this.simulationTimer)
    if (this.transitionTimeout) clearTimeout(this.transitionTimeout)
  }

  // Mid-leg, the guidance is deliberately generic ("keep going straight") no
  // matter what the upcoming turn is -- the turn itself is only previewed in the
  // THEN row, and gets its moment on the main arrow in handleArrival below.
  handlePosition(position) {
    if (this.arrived || this.transitioning) return

    const current = { lat: position.coords.latitude, lng: position.coords.longitude }
    const target = this.waypointsValue[this.currentIndexValue]
    if (!target) return

    const distance = this.haversineMeters(current, target)

    if (distance < ARRIVAL_THRESHOLD_METERS) {
      this.handleArrival(target)
      return
    }

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

  renderArrived() {
    this.arrived = true
    this.stopTracking()

    this.arrowTarget.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
    this.arrowTarget.style.transform = "rotate(0deg)"
    this.stepsCountTarget.textContent = "0"
    this.instructionTextTarget.textContent = "You've arrived!"
    this.nextRowTarget.classList.add("next-instruction-hidden")
  }

  // The camera button is a one-shot: once a photo's been taken for this walk,
  // hide it rather than letting the user retake/replace it.
  photoTaken() {
    this.cameraButtonTarget.classList.add("d-none")
  }

  handleError(error) {
    this.instructionTextTarget.textContent = error.code === error.PERMISSION_DENIED
      ? "Enable location access to continue"
      : "Waiting for a location signal…"
  }

  haversineMeters(a, b) {
    const R = 6371000
    const dLat = (b.lat - a.lat) * Math.PI / 180
    const dLng = (b.lng - a.lng) * Math.PI / 180
    const lat1 = a.lat * Math.PI / 180
    const lat2 = b.lat * Math.PI / 180
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
    return 2 * R * Math.asin(Math.sqrt(h))
  }
}
