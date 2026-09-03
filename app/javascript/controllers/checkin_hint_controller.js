import { Controller } from "@hotwired/stimulus"

// Plays a one-time-per-visit "check in" pencil-annotation hint (handwritten
// text + curved arrow, see components/_mood_checkin.scss's .checkin-hint)
// pointing at the mood-checkin avatar, to teach visitors that it's tappable.
// This is wired for a live demo, so it deliberately replays on every home
// page visit -- no localStorage/sessionStorage suppression -- including
// plain Turbo navigation, back/forward, bfcache restores (pageshow) and
// returning after the tab was backgrounded a few seconds (visibilitychange).
// The avatar itself is a separate sibling element (not inside .checkin-hint)
// so it stays fully visible/clickable throughout -- see pointer-events: none
// on .checkin-hint.
const REVEAL_DELAY_MS = 400
const TEXT_DRAW_MS = 700
const ARROW_DRAW_MS = 500
const HOLD_MS = 1200
const FADE_MS = 400
const PULSE_MS = 500
const BACKGROUND_THRESHOLD_MS = 3000

export default class extends Controller {
  static targets = ["hint", "text", "icon"]

  connect() {
    this.timeouts = []
    this.hiddenAt = null
    this.playing = false

    this.handlePageShow = this.handlePageShow.bind(this)
    this.handleVisibilityChange = this.handleVisibilityChange.bind(this)
    window.addEventListener("pageshow", this.handlePageShow)
    document.addEventListener("visibilitychange", this.handleVisibilityChange)

    this.play()
  }

  disconnect() {
    this.clearTimers()
    window.removeEventListener("pageshow", this.handlePageShow)
    document.removeEventListener("visibilitychange", this.handleVisibilityChange)
  }

  // Restores the page from the back-forward cache (mobile Safari/Chrome
  // back button, in particular) without Turbo re-rendering, so connect()
  // never fires again -- pageshow's persisted flag is the only reliable
  // signal for that case.
  handlePageShow(event) {
    if (event.persisted) this.play()
  }

  handleVisibilityChange() {
    if (document.hidden) {
      this.hiddenAt = Date.now()
      return
    }

    const wasHiddenLongEnough = this.hiddenAt && Date.now() - this.hiddenAt >= BACKGROUND_THRESHOLD_MS
    this.hiddenAt = null
    if (wasHiddenLongEnough) this.play()
  }

  play() {
    if (this.playing) return
    this.playing = true

    this.reset()

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.playReduced()
    } else {
      this.playFull()
    }
  }

  playReduced() {
    // No drawing motion or icon pulse -- just show the finished cue briefly,
    // then fade it out.
    this.hintTarget.classList.add("is-reduced-motion", "is-visible")
    this.schedule(() => this.hintTarget.classList.add("is-fading"), HOLD_MS)
    this.schedule(() => this.finish(), HOLD_MS + FADE_MS)
  }

  playFull() {
    this.schedule(() => {
      this.hintTarget.classList.add("is-visible")
    }, REVEAL_DELAY_MS)

    this.schedule(() => {
      this.hintTarget.classList.add("is-arrow-drawing")
    }, REVEAL_DELAY_MS + TEXT_DRAW_MS)

    this.schedule(() => {
      this.iconTarget.classList.add("is-pulsing")
    }, REVEAL_DELAY_MS + TEXT_DRAW_MS + ARROW_DRAW_MS)

    this.schedule(() => {
      this.iconTarget.classList.remove("is-pulsing")
    }, REVEAL_DELAY_MS + TEXT_DRAW_MS + ARROW_DRAW_MS + PULSE_MS)

    this.schedule(() => {
      this.hintTarget.classList.add("is-fading")
    }, REVEAL_DELAY_MS + TEXT_DRAW_MS + ARROW_DRAW_MS + HOLD_MS)

    this.schedule(() => {
      this.finish()
    }, REVEAL_DELAY_MS + TEXT_DRAW_MS + ARROW_DRAW_MS + HOLD_MS + FADE_MS)
  }

  finish() {
    this.playing = false
  }

  // Clears timers and animation classes back to the initial (invisible)
  // state, and forces a reflow so re-adding the same classes a moment later
  // reliably restarts the CSS animations instead of the browser coalescing
  // the no-op class churn.
  reset() {
    this.clearTimers()

    this.hintTarget.classList.remove("is-visible", "is-arrow-drawing", "is-fading", "is-reduced-motion")
    this.iconTarget.classList.remove("is-pulsing")

    // Not a Stimulus target -- the arrow SVG is dropped in verbatim from the
    // design spec (see the view), so we find its path by class instead of
    // adding a data-target attribute to it.
    const arrowPath = this.element.querySelector(".mood-check-hint__arrow-path")
    const length = Math.ceil(arrowPath.getTotalLength())
    arrowPath.style.strokeDasharray = length
    this.hintTarget.style.setProperty("--checkin-hint-arrow-length", length)

    void this.hintTarget.offsetWidth
  }

  schedule(fn, delay) {
    this.timeouts.push(setTimeout(fn, delay))
  }

  clearTimers() {
    this.timeouts.forEach(id => clearTimeout(id))
    this.timeouts = []
  }
}
