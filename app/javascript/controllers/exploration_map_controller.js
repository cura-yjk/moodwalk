import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Connects to data-controller="exploration-map"
export default class extends Controller {
  static values = {
    accessToken: String,
    center: Array,
    routes: Array
  }

  connect() {
    mapboxgl.accessToken = this.accessTokenValue

    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v12",
      center: this.centerValue,
      zoom: 13
    })

    this.map.on("load", () => this.#draw())
  }

  disconnect() {
    this.map?.remove()
  }

  #draw() {
    this.#drawRoutes()
    this.#drawCurrentLocationMarker()
    this.#fitBounds()
  }

  // Matches the solid route line used elsewhere in the app (see
  // map_controller.js) -- all walked routes share one source/layer since
  // they're drawn identically.
  #drawRoutes() {
    if (this.routesValue.length === 0) return

    this.map.addSource("routes", {
      type: "geojson",
      data: {
        type: "FeatureCollection",
        features: this.routesValue.map((coordinates) => ({
          type: "Feature",
          geometry: { type: "LineString", coordinates }
        }))
      }
    })

    this.map.addLayer({
      id: "routes",
      type: "line",
      source: "routes",
      layout: { "line-join": "round", "line-cap": "round" },
      paint: { "line-color": "#4a7c59", "line-width": 4 }
    })
  }

  #drawCurrentLocationMarker() {
    new mapboxgl.Marker({ color: "#4a7c59" }).setLngLat(this.centerValue).addTo(this.map)
  }

  #fitBounds() {
    const points = [this.centerValue, ...this.routesValue.flat()]
    if (points.length < 2) return

    const bounds = points.reduce(
      (bounds, point) => bounds.extend(point),
      new mapboxgl.LngLatBounds(points[0], points[0])
    )
    this.map.fitBounds(bounds, { padding: 60, duration: 0 })
  }
}
