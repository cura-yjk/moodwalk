import { Controller } from "@hotwired/stimulus"
import mapboxgl from "mapbox-gl"

// Connects to data-controller="map"
export default class extends Controller {
  static values = {
    accessToken: String,
    center: Array,
    route: Array
  }

  connect() {
    mapboxgl.accessToken = this.accessTokenValue

    this.map = new mapboxgl.Map({
      container: this.element,
      style: "mapbox://styles/mapbox/streets-v12",
      center: this.centerValue,
      zoom: 14
    })

    this.map.on("load", () => this.#drawRoute())
  }

  disconnect() {
    this.map?.remove()
  }

  #drawRoute() {
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

    new mapboxgl.Marker({ color: "#4a7c59" }).setLngLat(this.centerValue).addTo(this.map)

    const bounds = this.routeValue.reduce(
      (bounds, coordinate) => bounds.extend(coordinate),
      new mapboxgl.LngLatBounds(this.centerValue, this.centerValue)
    )
    this.map.fitBounds(bounds, { padding: 40, duration: 0 })
  }
}
