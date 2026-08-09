# frozen_string_literal: true

require "digest"
require "net/http"
require "stringio"

module Minecraft
  class TextureCacheDownloader < ApplicationService
    TEXTURE_HOST = "textures.minecraft.net"
    TEXTURE_PATH = %r{\A/texture/[0-9a-f]+\z}i
    MAX_TEXTURE_BYTES = 1.megabyte
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class ResponseTooLarge < StandardError; end

    def initialize(url:)
      @url = url.to_s
    end

    def call
      canonical_url = self.class.canonical_url(@url)
      return ServiceResult.failure(error: :unsafe_texture_url) unless canonical_url

      uri = URI.parse(canonical_url)

      payload = download(uri)
      return ServiceResult.failure(error: :texture_fetch_failed) unless payload

      inspected = Community::ImageUploadInspector.call(io: StringIO.new(payload), max_bytes: MAX_TEXTURE_BYTES)
      return ServiceResult.failure(error: :invalid_texture_image) unless inspected.success?
      return ServiceResult.failure(error: :invalid_texture_image) unless inspected.content_type == "image/png"

      sanitized = inspected.payload
      ServiceResult.success(
        payload: sanitized,
        content_type: inspected.content_type,
        width: inspected.width,
        height: inspected.height,
        sha256: Digest::SHA256.hexdigest(sanitized)
      )
    rescue URI::InvalidURIError
      ServiceResult.failure(error: :unsafe_texture_url)
    rescue ResponseTooLarge
      ServiceResult.failure(error: :texture_too_large)
    rescue StandardError
      ServiceResult.failure(error: :texture_fetch_failed)
    end

    def self.allowed_url?(value)
      uri = value.is_a?(URI) ? value : URI.parse(value.to_s)
      uri.is_a?(URI::HTTPS) &&
        uri.host&.casecmp?(TEXTURE_HOST) &&
        (uri.port.nil? || uri.port == 443) &&
        uri.userinfo.nil? &&
        uri.query.nil? &&
        uri.fragment.nil? &&
        uri.path.match?(TEXTURE_PATH)
    rescue URI::InvalidURIError
      false
    end

    def self.canonical_url(value)
      uri = value.is_a?(URI) ? value : URI.parse(value.to_s)
      return nil unless uri.scheme.in?(%w[http https])
      return nil unless uri.host&.casecmp?(TEXTURE_HOST)
      return nil unless [ 80, 443 ].include?(uri.port)
      return nil unless uri.userinfo.nil? && uri.query.nil? && uri.fragment.nil?
      return nil unless uri.path.match?(TEXTURE_PATH)

      URI::HTTPS.build(host: TEXTURE_HOST, path: uri.path).to_s
    rescue URI::InvalidURIError
      nil
    end

    private

    def download(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)
        raise ResponseTooLarge if response.content_length.to_i > MAX_TEXTURE_BYTES

        payload = +"".b
        response.read_body do |chunk|
          payload << chunk
          raise ResponseTooLarge if payload.bytesize > MAX_TEXTURE_BYTES
        end
        payload
      end
    end
  end
end
