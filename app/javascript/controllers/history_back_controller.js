// app/javascript/controllers/history_back_controller.js
import { Controller } from "@hotwired/stimulus"

// Navigates back to whatever page the user actually came from, instead of a
// hardcoded route -- for buttons that can be reached from more than one place.
export default class extends Controller {
  static values = { fallbackUrl: String }

  back(event) {
    event.preventDefault()

    if (window.history.length > 1) {
      window.history.back()
    } else if (this.hasFallbackUrlValue) {
      Turbo.visit(this.fallbackUrlValue)
    }
  }
}
