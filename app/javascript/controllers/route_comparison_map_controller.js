import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Draws the suggested journey route and the path the user actually walked on
// one map, so they can be compared on the walk-complete screen. Both are
// GeoJSON LineStrings of [lng, lat] pairs: `suggested` from
// Journey#route_coordinates, `actual` from Walk#actual_route_coordinates.
export default class extends Controller {
  static values = {
    accessToken: String,
    center: Array,
    suggested: Array,
    actual: Array
  }

  connect() {
    mapboxgl.accessToken = this.accessTokenValue

    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v12",
      center: this.centerValue,
      zoom: 14,
      interactive: false
    })

    this.map.on("load", () => this.#draw())
  }

  disconnect() {
    this.map?.remove()
  }

  #draw() {
    // Suggested route: the app green, but kept faint so it reads as a
    // reference underlay rather than competing with the actual route.
    this.#addLine("suggested-route", this.suggestedValue, "#4a7c59", 3, { opacity: 0.25 })
    // Actual route: dashed terracotta so the two read as distinct even where
    // they overlap.
    this.#addLine("actual-route", this.actualValue, "#d9762b", 4, { dashArray: [1.5, 1.2] })

    new mapboxgl.Marker({ color: "#4a7c59" }).setLngLat(this.centerValue).addTo(this.map)

    this.#fitBounds([...this.suggestedValue, ...this.actualValue])
  }

  #addLine(id, coordinates, color, width, { dashArray = null, opacity = 1 } = {}) {
    if (!coordinates || coordinates.length < 2) return

    this.map.addSource(id, {
      type: "geojson",
      data: { type: "Feature", geometry: { type: "LineString", coordinates } }
    })

    const paint = { "line-color": color, "line-width": width, "line-opacity": opacity }
    if (dashArray) paint["line-dasharray"] = dashArray

    this.map.addLayer({
      id,
      type: "line",
      source: id,
      layout: { "line-join": "round", "line-cap": "round" },
      paint
    })
  }

  #fitBounds(points) {
    if (points.length < 2) return

    const bounds = points.reduce(
      (bounds, point) => bounds.extend(point),
      new mapboxgl.LngLatBounds(points[0], points[0])
    )
    this.map.fitBounds(bounds, { padding: 40, duration: 0 })
  }
}
