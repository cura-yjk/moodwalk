import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { shareUrl: String }

  async share() {
    await fetch(this.shareUrlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      }
    })
  }
}
