import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]

  showLoading() {
    this.frameTarget.classList.add("is-loading")
  }
}
