import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["track"]

  next() {
    this.scrollByCard(1)
  }

  prev() {
    this.scrollByCard(-1)
  }

  scrollByCard(direction) {
    const card = this.trackTarget.querySelector(".carousel-item")
    if (!card) return

    const gap = parseFloat(getComputedStyle(this.trackTarget).columnGap || 0)
    const distance = card.offsetWidth + gap

    this.trackTarget.scrollBy({ left: distance * direction, behavior: "smooth" })
  }
}
