import { Controller } from "@hotwired/stimulus"

// Drives the "how long do you have?" bottom sheet that appears after tapping
// a mood card on the homepage (see pages/_theme_picker.html.erb): fills in
// the sheet with the tapped theme's icon/label, defaults duration to "No
// rush", and lets the user swap duration before submitting the one shared
// form (theme_key + duration_minutes) to JourneysController#create.
export default class extends Controller {
  static targets = ["backdrop", "sheet", "icon", "title", "subtitle", "themeKeyInput", "durationInput", "option"]

  open(event) {
    const { themeKey, themeLabel, themeSubtitle, themeIcon } = event.params

    this.themeKeyInputTarget.value = themeKey
    this.sheetTarget.dataset.theme = themeKey
    this.titleTarget.textContent = themeLabel
    this.subtitleTarget.textContent = themeSubtitle
    this.iconTarget.innerHTML = `<i class="${themeIcon}"></i>`
    this.highlight("")

    this.backdropTarget.classList.add("is-open")
    this.sheetTarget.classList.add("is-open")
  }

  close() {
    this.backdropTarget.classList.remove("is-open")
    this.sheetTarget.classList.remove("is-open")
  }

  selectDuration(event) {
    this.highlight(event.params.minutes)
  }

  highlight(minutes) {
    this.durationInputTarget.value = minutes
    this.optionTargets.forEach((option) => {
      option.classList.toggle("selected", option.dataset.durationPickerMinutesParam === String(minutes))
    })
  }
}
