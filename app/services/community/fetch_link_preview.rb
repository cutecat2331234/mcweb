# frozen_string_literal: true

require "net/http"
require "uri"
require "cgi"

module Community
  class FetchLinkPreview < ApplicationService
    TIMEOUT = 5
    MAX_BODY = 256_000

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Invalid URL.") unless UrlSafety.public_http_url?(@url)

      cached = Rails.cache.read(cache_key)
      return ServiceResult.success(cached) if cached

      preview = scrape_preview
      Rails.cache.write(cache_key, preview, expires_in: 1.day) if preview
      ServiceResult.success(preview)
    rescue StandardError
      ServiceResult.failure(error: "Preview unavailable.")
    end

    private

    def cache_key
      "forum/link_preview/#{Digest::SHA256.hexdigest(@url)}"
    end

    def scrape_preview
      return nil unless UrlSafety.public_http_url?(@url)

      uri = URI.parse(@url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
        http.get(uri.request_uri, { "User-Agent" => "McWebBot/1.0" })
      end
      return nil unless response.is_a?(Net::HTTPSuccess)

      body = response.body.to_s.byteslice(0, MAX_BODY)
      {
        url: @url,
        title: meta_content(body, "og:title") || meta_content(body, "title") || uri.host,
        description: meta_content(body, "og:description") || meta_content(body, "description"),
        image_url: meta_content(body, "og:image")
      }
    end

    def meta_content(html, property)
      if (match = html.match(/<meta[^>]+property=["']#{Regexp.escape(property)}["'][^>]+content=["']([^"']+)["']/i))
        CGI.unescapeHTML(match[1])
      elsif (match = html.match(/<meta[^>]+content=["']([^"']+)["'][^>]+property=["']#{Regexp.escape(property)}["']/i))
        CGI.unescapeHTML(match[1])
      elsif property == "title" && (match = html.match(/<title[^>]*>([^<]+)<\/title>/i))
        CGI.unescapeHTML(match[1].strip)
      end
    end
  end
end
