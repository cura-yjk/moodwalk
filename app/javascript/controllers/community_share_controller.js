import { Controller } from "@hotwired/stimulus"

const RATING_LABELS = { 1: "Poor", 2: "Fair", 3: "Good", 4: "Great", 5: "Excellent" }

// Drives the "Share to Community" modal on walks#edit (see mockup): star
// rating + optional review, submitted via PATCH to WalksController#share
// without leaving the walk-complete page. Success surfaces as a flash-style
// toast matching shared/_flashes.html.erb rather than a real redirect/flash,
// since the page never reloads.
export default class extends Controller {
  static targets = [
    "button", "buttonIcon", "buttonLabel",
    "modal", "stars", "ratingLabel",
    "review", "charCount",
    "submitButton", "submitLabel"
  ]
  static values = { shareUrl: String, shared: Boolean, rating: Number }

  connect() {
    this.currentRating = this.ratingValue || 0
    this.renderStars()
    this.renderButton()
  }

  // Copies whatever the user has typed in the "Anything you want to
  // remember?" reflection field into the review box the first time the
  // modal opens, so they aren't starting from a blank box -- but only if
  // they haven't already written something review-specific.
  prefillReview() {
    if (this.reviewTarget.value.trim().length > 0) return

    const journal = document.getElementById("journal-input")
    if (journal && journal.value.trim().length > 0) {
      this.reviewTarget.value = journal.value.slice(0, 150)
      this.countChars()
    }
  }

  setRating(event) {
    this.currentRating = Number(event.currentTarget.dataset.rating)
    this.renderStars()
  }

  countChars() {
    this.charCountTarget.textContent = this.reviewTarget.value.length
  }

  async share() {
    this.submitButtonTarget.disabled = true
    this.submitLabelTarget.textContent = "Sharing..."

    try {
      const response = await fetch(this.shareUrlValue, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Content-Type": "application/x-www-form-urlencoded"
        },
        body: new URLSearchParams({
          rating: this.currentRating || "",
          review: this.reviewTarget.value
        })
      })

      if (!response.ok) throw new Error("Share failed")

      this.sharedValue = true
      this.renderButton()
      this.hideModal()
      this.showFlash("info", "Shared to the community! 🌿")
    } catch (error) {
      console.error(error)
      this.showFlash("warning", "Couldn't share right now. Please try again.")
    } finally {
      this.submitButtonTarget.disabled = false
      this.submitLabelTarget.textContent = "Share to Community"
    }
  }

  renderStars() {
    this.starsTarget.querySelectorAll(".share-star").forEach(star => {
      star.classList.toggle("active", Number(star.dataset.rating) <= this.currentRating)
    })

    this.ratingLabelTarget.textContent = RATING_LABELS[this.currentRating] || " "
  }

  renderButton() {
    if (!this.hasButtonTarget) return

    this.buttonIconTarget.classList.toggle("fa-arrow-up-from-bracket", !this.sharedValue)
    this.buttonIconTarget.classList.toggle("fa-check", this.sharedValue)
    this.buttonLabelTarget.textContent = this.sharedValue ? "Posted" : "Post"
  }

  hideModal() {
    window.bootstrap.Modal.getOrCreateInstance(this.modalTarget).hide()
  }

  // Builds the same alert markup as shared/_flashes.html.erb (so it matches
  // the app's existing flash design) and drops it in as a toast, since this
  // action doesn't redirect/reload the page for a real flash to render on.
  showFlash(type, message) {
    document.querySelectorAll(".js-flash-toast").forEach(el => el.remove())

    const flash = document.createElement("div")
    flash.className = `alert alert-${type} alert-dismissible fade show js-flash-toast`
    flash.setAttribute("role", "alert")
    flash.textContent = message

    const closeButton = document.createElement("button")
    closeButton.type = "button"
    closeButton.className = "btn-close"
    closeButton.setAttribute("data-bs-dismiss", "alert")
    closeButton.setAttribute("aria-label", "Close")
    flash.appendChild(closeButton)

    document.body.appendChild(flash)
    setTimeout(() => flash.remove(), 4000)
  }
}
