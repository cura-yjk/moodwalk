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

// GPS breadcrumb tracking (persisting where the user actually walked, vs. the
// suggested route). Fixes worse than this accuracy are dropped as noise; fixes
// closer than this to the previous kept one are skipped so a stationary walker
// doesn't pile up near-duplicate points; buffered points POST in batches.
const MAX_ACCURACY_METERS = 40
const MIN_BREADCRUMB_GAP_METERS = 5
const BREADCRUMB_BATCH_SIZE = 10

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

  static targets = ["arrow", "instructionText", "nextRow", "nextInstructionText", "cameraButton", "endWalkForm", "distanceField", "stepsField"]
  static values = { waypoints: Array, currentIndex: { type: Number, default: 0 }, devMode: Boolean, attachPhotoUrl: String, trackUrl: String }

  connect() {
    this.arrived = false
    this.transitioning = false
    // Cumulative great-circle distance actually covered so far, built up from
    // consecutive position fixes -- this is what gets submitted as the walk's
    // real actual_distance/actual_steps, rather than the route's planned distance.
    this.traveledMeters = 0

    // Where the user has actually walked, streamed to the server in batches.
    // trackBuffer holds points not yet POSTed; lastRecordedPoint survives each
    // flush so the min-gap throttle keeps working across batches.
    this.trackBuffer = []
    this.lastRecordedPoint = null
    // A full-page navigation (the "End Walk" button) can beat disconnect(), so
    // also flush on pagehide with keepalive so the tail of the walk isn't lost.
    this.flushOnPageHide = () => this.flushBreadcrumbs({ keepalive: true })
    window.addEventListener("pagehide", this.flushOnPageHide)

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
      if (this.flushOnPageHide) {
      window.removeEventListener("pagehide", this.flushOnPageHide)
      this.flushOnPageHide = null
    }
    this.flushBreadcrumbs({ keepalive: true })
  }

  // Buffers one GPS fix as a breadcrumb, dropping low-accuracy noise and points
  // too close to the last kept one. Runs on every position update -- including
  // after arrival and during turn transitions -- so the recorded path doesn't
  // have gaps where handlePosition bails out early. Simulated positions (dev
  // ?simulate=) have no accuracy/timestamp, so those checks are skipped.
  recordBreadcrumb(position) {
    if (!this.hasTrackUrlValue) return

    const { latitude, longitude, accuracy } = position.coords
    if (accuracy != null && accuracy > MAX_ACCURACY_METERS) return

    const point = { lat: latitude, lng: longitude }
    if (this.lastRecordedPoint &&
        this.haversineMeters(this.lastRecordedPoint, point) < MIN_BREADCRUMB_GAP_METERS) {
      return
    }
    this.lastRecordedPoint = point

    this.trackBuffer.push({
      latitude,
      longitude,
      accuracy_meters: accuracy ?? null,
      recorded_at: new Date(position.timestamp ?? Date.now()).toISOString()
    })

    if (this.trackBuffer.length >= BREADCRUMB_BATCH_SIZE) this.flushBreadcrumbs()
  }

  // POSTs whatever breadcrumbs are buffered and clears them. `keepalive` lets
  // the request outlive the page during the "End Walk" navigation (fetch still
  // sends the CSRF header that way, unlike navigator.sendBeacon).
  flushBreadcrumbs({ keepalive = false } = {}) {
    if (this.trackBuffer.length === 0) return

    const points = this.trackBuffer.splice(0)
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.trackUrlValue, {
      method: "POST",
      keepalive,
      headers: { "Content-Type": "application/json", "X-CSRF-Token": csrfToken },
      body: JSON.stringify({ points })
    }).catch(() => {
      // Best-effort: if a batch fails to send, put it back so the next flush
      // (or the pagehide flush) can retry it rather than losing it outright.
      this.trackBuffer.unshift(...points)
    })
  }

  // Mid-leg, the guidance is deliberately generic ("keep going straight") no
  // matter what the upcoming turn is -- the turn itself is only previewed in the
  // THEN row, and gets its moment on the main arrow in handleArrival below.
  handlePosition(position) {

    // Record where the user is before any early return below, so the saved
    // path stays continuous even after arrival / during turn transitions.
    this.recordBreadcrumb(position)

    // Ignore updates while we've already arrived, or while mid-transition
    // between one waypoint and the next (avoids double-triggering arrival).
    if (this.arrived || this.transitioning) return

    const current = { lat: position.coords.latitude, lng: position.coords.longitude }

    // Add this leg's distance to the running total before overwriting
    // lastPosition -- there's nothing to measure from on the very first fix.
    if (this.lastPosition) {
      this.traveledMeters += this.haversineMeters(this.lastPosition, current)
      this.updateTraveledFields()
    }

    // Remembered so photoTaken can tag a photo with where the walker
    // actually was when they took it, not just the route's start point.
    this.lastPosition = current

    const target = this.waypointsValue[this.currentIndexValue]
    if (!target) return

    const distance = this.haversineMeters(current, target)

    // Close enough to the current target waypoint -- treat this as arrival
    // there, rather than continuing to show "keep going straight."
    if (distance < ARRIVAL_THRESHOLD_METERS) {
      this.handleArrival(target)
      return
    }

    // Still en route: reset the arrow to neutral and show the generic instruction.
    this.arrowTarget.style.transform = "rotate(0deg)"
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
  // a checkmark and stops all tracking/timers since there's nothing left to
  // navigate toward.
  renderArrived() {
    this.arrived = true
    this.stopTracking()

    this.arrowTarget.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
    this.arrowTarget.style.transform = "rotate(0deg)"
    this.instructionTextTarget.textContent = "You've arrived!"
    this.nextRowTarget.classList.add("next-instruction-hidden")
  }

  photoTaken(event) {
  const file = event.target.files[0]
  if (!file) return

  const formData = new FormData()
  formData.append("walk[photo]", file)
  if (this.lastPosition) {
    formData.append("walk[photo_latitude]", this.lastPosition.lat)
    formData.append("walk[photo_longitude]", this.lastPosition.lng)
  }

  const csrfToken = document.querySelector('meta[name="csrf-token"]').content

  // Tracked so endWalk can wait for this to finish before submitting --
  // otherwise a tap right after snapping a photo can complete the walk
  // before the upload has actually landed.
  this.photoUploadPromise = fetch(this.attachPhotoUrlValue, {
    method: "PATCH",
    headers: { "X-CSRF-Token": csrfToken },
    body: formData
  })
    .then((response) => {
      if (response.ok) {
        this.showPhotoCaptured()
      } else {
        alert("Photo upload failed — try again.")
      }
    })
    .catch(() => alert("Photo upload failed — check your connection."))
    .finally(() => { this.photoUploadPromise = null })
  }

  // Swaps the camera icon for a checkmark once a photo has successfully
  // uploaded, rather than hiding the button -- keeps a persistent on-screen
  // confirmation instead of the control just vanishing. The input is disabled
  // so tapping the button again doesn't reopen the camera for a walk that
  // already has a photo attached (only one photo per walk is supported).
  showPhotoCaptured() {
    this.cameraButtonTarget.classList.add("camera-btn-captured")
    this.cameraButtonTarget.querySelector("input").disabled = true
    this.cameraButtonTarget.querySelector("svg").outerHTML =
      '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>'
  }

  // Intercepts the End Walk button's submit -- if a photo upload is still in
  // flight, waits for it to settle first so the edit page doesn't render
  // before the attachment has actually landed (see attach_photo race).
  endWalk(event) {
    if (!this.photoUploadPromise) return // nothing pending, let the form submit normally

    event.preventDefault()

    this.photoUploadPromise.finally(() => {
      this.endWalkFormTarget.requestSubmit()
    })
  }

  // Geolocation failure handler -- distinguishes "user said no" (permission
  // denied) from other transient issues (still waiting for a GPS fix, etc.)
  // so the on-screen message tells the user what to actually do about it.
  handleError(error) {
    this.instructionTextTarget.textContent = error.code === error.PERMISSION_DENIED
      ? "Enable location access to continue"
      : "Waiting for a location signal…"
  }

  // Mirrors the running distance total into the hidden form fields so
  // whatever gets submitted with "End Walk" reflects the ground actually
  // covered, not the route's planned distance.
  updateTraveledFields() {
    if (this.hasDistanceFieldTarget) this.distanceFieldTarget.value = (this.traveledMeters / 1000).toFixed(2)
    if (this.hasStepsFieldTarget) this.stepsFieldTarget.value = Math.round(this.traveledMeters / STEP_LENGTH_METERS)
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
