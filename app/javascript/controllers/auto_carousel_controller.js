import { Controller } from "@hotwired/stimulus"

// Rotates a Bootstrap carousel on its own.
//
// Not data-bs-ride="carousel": Bootstrap starts those once, on the window's
// load event, and Turbo swaps pages without one - so a carousel reached by
// following a link would sit still. connect() runs every time the carousel
// lands on the page, however it got there.
//
// Pauses while the pointer is over it, and doesn't rotate at all when the
// device asks for reduced motion: moving content is what someone who's
// overwhelmed may have turned off on purpose. The arrows and swiping keep
// working either way - Bootstrap handles those without an instance.
export default class extends Controller {
  static values = { interval: { type: Number, default: 6000 } }

  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.carousel = window.bootstrap.Carousel.getOrCreateInstance(this.element, {
      interval: this.intervalValue,
      pause: "hover"
    })
    this.carousel.cycle()
  }

  disconnect() {
    this.carousel?.dispose()
  }
}
