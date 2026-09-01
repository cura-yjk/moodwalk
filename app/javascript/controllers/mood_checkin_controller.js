import { Controller } from "@hotwired/stimulus"

// Drives the optional homepage mood check-in: tapping the header avatar
// opens a small bottom sheet with 5 mood options (the same MOOD_ICONS artwork
// as the walk-complete mood picker); picking one (or dismissing without
// answering) closes it again. The chosen mood is only ever used to swap
// which icon the avatar shows -- it's remembered in localStorage purely as a
// client-side nicety (so the avatar doesn't reset to neutral on every page
// load), not synced to the server.
const STORAGE_KEY = "moodwalk:checkin-mood"

export default class extends Controller {
  static targets = ["avatarFace", "backdrop", "sheet"]
  static values = { icons: Object }

  connect() {
    const savedMood = this.readSavedMood()
    if (savedMood) this.showFace(savedMood)
  }

  open() {
    this.backdropTarget.classList.add("is-open")
    this.sheetTarget.classList.add("is-open")
    // Matches duration_picker_controller.js -- the navbar's z-index would
    // otherwise sit on top of this bottom sheet too.
    document.body.classList.add("navbar-hidden")
  }

  close() {
    this.backdropTarget.classList.remove("is-open")
    this.sheetTarget.classList.remove("is-open")
    document.body.classList.remove("navbar-hidden")
  }

  select(event) {
    const mood = event.currentTarget.dataset.mood
    this.showFace(mood)
    this.saveMood(mood)
    this.close()
  }

  showFace(mood) {
    const iconUrl = this.iconsValue[mood]
    if (iconUrl) this.avatarFaceTarget.src = iconUrl
  }

  readSavedMood() {
    try {
      return window.localStorage.getItem(STORAGE_KEY)
    } catch {
      return null
    }
  }

  saveMood(mood) {
    try {
      window.localStorage.setItem(STORAGE_KEY, mood)
    } catch {
      // Private browsing / storage disabled -- the check-in still works for
      // this page view, it just won't be remembered next time.
    }
  }
}
