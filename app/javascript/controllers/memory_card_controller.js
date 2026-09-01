import { Controller } from "@hotwired/stimulus"
import { toBlob } from "html-to-image"

export default class extends Controller {
  static targets = ["quote", "topbar"]
  static values = { quoteUrl: String, moodAfter: String, reflection: String }

  connect() {
    this.fetchQuote()
  }

  async fetchQuote() {
    const response = await fetch(this.quoteUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ mood_after: this.moodAfterValue, reflection: this.reflectionValue })
    })

    const data = await response.json()
    if (data.quote) this.quoteTarget.textContent = data.quote
  }

  async download() {
    // visibility (not d-none/display:none) so the topbar keeps its spot in
    // the flex layout -- hiding it with display:none let the flex:1 content
    // block below expand into the freed space, visibly shifting the whole
    // page up for the duration of the capture and snapping back after.
    this.topbarTarget.classList.add("invisible")
    // pixelRatio pinned rather than left to devicePixelRatio -- this renders
    // the real DOM via an SVG foreignObject (unlike html2canvas, which
    // reimplements CSS/image rendering by hand and mangled gradients and
    // wide-gamut photo colors), so it needs a fixed target resolution.
    const blob = await toBlob(this.element, { pixelRatio: 2, cacheBust: true })
    this.topbarTarget.classList.remove("invisible")

    const link = document.createElement("a")
    link.href = URL.createObjectURL(blob)
    link.download = "moodwalk-memory.png"
    link.click()
    URL.revokeObjectURL(link.href)
  }
}
