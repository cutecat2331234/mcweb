# frozen_string_literal: true

module Minecraft
  class ValidateSyncFileUrl < ApplicationService
    SYNC_PATH = "/minecraft/sync/"

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "Sync URL is required.") if @url.blank?

      uri = URI.parse(@url)
      return ServiceResult.failure(error: "Sync URL scheme is not allowed.") unless allowed_scheme?(uri)
      return ServiceResult.failure(error: "Sync URL host is not allowed.") unless allowed_host?(uri)
      return ServiceResult.failure(error: "Sync URL path is not allowed.") unless uri.path.include?(SYNC_PATH)

      ServiceResult.success(true)
    rescue URI::InvalidURIError
      ServiceResult.failure(error: "Sync URL is invalid.")
    end

    private

    def allowed_scheme?(uri)
      return true if uri.scheme == "https"
      return true if uri.scheme == "http" && loopback_host?(uri.host)

      false
    end

    def allowed_host?(uri)
      host = uri.host.to_s.downcase
      return false if host.blank?
      return true if loopback_host?(host)
      return false if blocked_host?(host)
      return false unless UrlSafety.public_http_url?(@url)

      true
    end

    def loopback_host?(host)
      host = host.to_s.delete_prefix("[").delete_suffix("]")
      return true if %w[localhost 127.0.0.1 ::1].include?(host.downcase)

      IPAddr.new(host).loopback?
    rescue IPAddr::InvalidAddressError
      false
    end

    def blocked_host?(host)
      host = host.downcase
      return true if UrlSafety::BLOCKED_HOSTS.include?(host)
      return true if host.end_with?(".local", ".internal", ".localhost")

      false
    end
  end
end
