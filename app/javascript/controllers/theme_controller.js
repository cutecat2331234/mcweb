import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { storageKey: { type: String, default: "mc-theme" } }

  connect() {
    this.apply(this.storedTheme() || this.systemTheme())
  }

  toggle() {
    const next = document.documentElement.classList.contains("dark") ? "light" : "dark"
    this.apply(next)
    localStorage.setItem(this.storageKeyValue, next)
  }

  apply(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark")
    this.updateToggleLabel(theme)
  }

  storedTheme() {
    return localStorage.getItem(this.storageKeyValue)
  }

  systemTheme() {
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light"
  }

  updateToggleLabel(theme) {
    const label = theme === "dark" ? "☀" : "☾"
    this.element.querySelectorAll("[data-theme-label]").forEach((el) => {
      el.textContent = label
    })
    this.element.setAttribute("aria-label", theme === "dark" ? "Switch to light mode" : "Switch to dark mode")
  }
}
