import { Controller } from "@hotwired/stimulus"

// Fills the "Start walking" form's hidden mood_before field with whatever
// mood the user last picked in the homepage check-in (see
// mood_checkin_controller.js), if any. This is the only way that mood ever
// reaches the server -- the check-in itself is purely client-side/optional,
// so a walk simply has no mood_before when nothing was ever picked.
const STORAGE_KEY = "moodwalk:checkin-mood"

export default class extends Controller {
  static targets = ["field"]

  connect() {
    try {
      const mood = window.localStorage.getItem(STORAGE_KEY)
      if (mood) this.fieldTarget.value = mood
    } catch {
      // Private browsing / storage disabled -- the walk just starts with no
      // mood_before, same as if the user never checked in.
    }
  }
}
