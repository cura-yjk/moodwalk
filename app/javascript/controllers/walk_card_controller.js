import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import mapboxgl from "mapbox-gl"

// Connects to data-controller="walk-card"
//
// Tapping a walks#index history card opens the memory card page, same as
// before. The map-toggle icon flips the card in place to preview the
// route on the back instead -- its action carries a Stimulus ":stop"
// modifier so that tap never bubbles up into the card's own open action.
export default class extends Controller {
  static targets = ["inner", "map"]
  static values = {
    accessToken: String,
    route: Array,
    memoryUrl: String
  }

  open() {
    Turbo.visit(this.memoryUrlValue)
  }

  // No-op target for the Start button -- its :stop modifier keeps the click
  // from bubbling into #open (which would navigate to the memory page
  // instead of following the button's own link to the walk preview page).
  stopPropagation() {}

  flip() {
    this.innerTarget.classList.toggle("flipped")

    // The map container has zero size until the card is flipped, so Mapbox
    // can't be initialized on connect() -- do it lazily the first time the
    // back is actually shown.
    if (this.innerTarget.classList.contains("flipped") && !this.map) {
      this.#buildMap()
    }
  }

  #buildMap() {
    mapboxgl.accessToken = this.accessTokenValue

    this.map = new mapboxgl.Map({
      container: this.mapTarget,
      style: "mapbox://styles/mapbox/streets-v12",
      center: this.routeValue[0],
      zoom: 13,
      interactive: false
    })

    this.map.on("load", () => {
      this.map.addSource("route", {
        type: "geojson",
        data: {
          type: "Feature",
          geometry: { type: "LineString", coordinates: this.routeValue }
        }
      })

      this.map.addLayer({
        id: "route",
        type: "line",
        source: "route",
        layout: { "line-join": "round", "line-cap": "round" },
        paint: { "line-color": "#4a7c59", "line-width": 4 }
      })

      const bounds = this.routeValue.reduce(
        (bounds, point) => bounds.extend(point),
        new mapboxgl.LngLatBounds(this.routeValue[0], this.routeValue[0])
      )
      this.map.fitBounds(bounds, { padding: 24, duration: 0 })
    })
  }

  disconnect() {
    this.map?.remove()
  }
}
