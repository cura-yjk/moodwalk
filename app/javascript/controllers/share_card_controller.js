import { Controller } from "@hotwired/stimulus"
import html2canvas from "html2canvas"

export default class extends Controller {
  static targets = ["card", "afterIcon", "afterValue", "quote", "moodInput", "reflectionInput"]
  static values = { quoteUrl: String, moodIconUrls: Object }

  async share() {
    const moodAfter = this.selectedMood()
    const reflection = this.reflectionInputTarget.value

    const quote = await this.fetchQuote(moodAfter, reflection)

    this.quoteTarget.textContent = quote
    this.afterValueTarget.textContent = moodAfter
    this.afterIconTarget.src = this.moodIconUrlsValue[moodAfter]

    this.cardTarget.classList.remove("d-none")
    const canvas = await html2canvas(this.cardTarget)
    this.cardTarget.classList.add("d-none")

    canvas.toBlob((blob) => this.deliver(blob))
  }

  selectedMood() {
    return this.moodInputTargets.find((input) => input.checked)?.value
  }

  async fetchQuote(moodAfter, reflection) {
    const response = await fetch(this.quoteUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ mood_after: moodAfter, reflection })
    })

    const data = await response.json()
    return data.quote || ""
  }

  async deliver(blob) {
    const file = new File([blob], "moodwalk-share.png", { type: "image/png" })

    if (navigator.canShare && navigator.canShare({ files: [file] })) {
      await navigator.share({ files: [file], title: "MoodWalk" })
    } else {
      const link = document.createElement("a")
      link.href = URL.createObjectURL(blob)
      link.download = "moodwalk-share.png"
      link.click()
    }
  }
}
