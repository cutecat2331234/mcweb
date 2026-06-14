// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Wappalyzer 等工具用于识别 Ruby on Rails 的 JS 指纹
if (typeof window !== "undefined") {
  window._rails_loaded = true
}
