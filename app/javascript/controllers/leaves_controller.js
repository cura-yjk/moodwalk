import { Controller } from "@hotwired/stimulus"

// A soft, brief "peaceful journey" celebration that plays once when this
// layer connects (the Walk Complete screen loading): a light scatter of
// leaves, ribbons, and tiny drifting particles carried by a gentle breeze,
// alongside a soft glow near the top of the screen (see .entrance-glow in
// walks/_edit.scss). Deliberately calm and understated -- not a confetti
// burst. Spawn delay is squared so most particles appear within the first
// ~1-1.5s and the rest trickle in and taper off; each particle's own drift
// is slow, and the whole effect is fully settled by ~5-6s.
const COLORS = [
  "#9CC69C", "#9CC69C", // soft green
  "#B8CBBB", "#B8CBBB", // sage
  "#EFE3A3", "#EFE3A3", // pale yellow
  "#E8DCC3", "#E8DCC3", // warm beige
  "#E3AE7E"              // soft orange -- kept rare
]

const PARTICLE_TYPES = ["leaf", "leaf", "ribbon", "ribbon", "dot", "dot", "dot"]

const PARTICLE_COUNT = 13
const SPAWN_WINDOW_SECONDS = 2.2

export default class extends Controller {
  connect() {
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    const fragment = document.createDocumentFragment()
    for (let i = 0; i < PARTICLE_COUNT; i++) fragment.appendChild(this.buildParticle())
    this.element.appendChild(fragment)
  }

  disconnect() {
    this.element.querySelectorAll(".particle").forEach(particle => particle.remove())
  }

  buildParticle() {
    const type = PARTICLE_TYPES[Math.floor(Math.random() * PARTICLE_TYPES.length)]
    const particle = document.createElement("span")
    particle.className = `particle particle--${type}`

    // Squaring the random delay biases spawns toward the start of the
    // window, so the effect is strongest early on and gradually tapers
    // rather than spawning at a constant rate.
    const delay = Math.pow(Math.random(), 2) * SPAWN_WINDOW_SECONDS
    const duration = 2.8 + Math.random() * 1.8 // slow, unhurried drift -- no confetti snap
    const drift = (Math.random() - 0.5) * 100 // gentle sideways carry, like a light breeze
    const fall = 16 + Math.random() * 16
    const peakOpacity = (0.3 + Math.random() * 0.2).toFixed(2) // 30-50%, per spec
    const blur = Math.random() < 0.4 ? (0.5 + Math.random() * 2).toFixed(1) : 0 // some read as "further away"
    const color = COLORS[Math.floor(Math.random() * COLORS.length)]

    let width, height, rotateStart, rotateEnd

    if (type === "leaf") {
      width = height = 9 + Math.random() * 7
      rotateStart = (Math.random() - 0.5) * 50
      rotateEnd = rotateStart + (Math.random() - 0.5) * 70
    } else if (type === "ribbon") {
      width = 3 + Math.random() * 2
      height = 14 + Math.random() * 14
      rotateStart = (Math.random() - 0.5) * 40
      rotateEnd = rotateStart + (Math.random() - 0.5) * 60
    } else {
      // Tiny organic particles stay basically still in rotation -- they're
      // small enough that spin would just read as noise, not motion.
      width = height = 3 + Math.random() * 4
      rotateStart = 0
      rotateEnd = 0
    }

    particle.style.left = `${Math.random() * 100}%`
    particle.style.setProperty("--width", `${width}px`)
    particle.style.setProperty("--height", `${height}px`)
    particle.style.setProperty("--particle-color", color)
    particle.style.setProperty("--drift", `${drift}px`)
    particle.style.setProperty("--fall", `${fall}vh`)
    particle.style.setProperty("--rotate-start", `${rotateStart}deg`)
    particle.style.setProperty("--rotate-end", `${rotateEnd}deg`)
    particle.style.setProperty("--peak-opacity", peakOpacity)
    particle.style.setProperty("--blur", `${blur}px`)
    particle.style.animationDuration = `${duration}s`
    particle.style.animationDelay = `${delay}s`

    particle.addEventListener("animationend", () => particle.remove())

    return particle
  }
}
