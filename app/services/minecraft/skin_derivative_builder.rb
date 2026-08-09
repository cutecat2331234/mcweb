# frozen_string_literal: true

require "digest"
require "vips"

module Minecraft
  class SkinDerivativeBuilder < ApplicationService
    MINIMUM_WIDTH = 64
    MINIMUM_HEIGHT = 32

    def initialize(payload:)
      @payload = payload.to_s.b
    end

    def call
      # A single source image is cropped several times in different regions.
      # Sequential access can no longer seek back after the first derivative.
      image = Vips::Image.new_from_buffer(@payload, "")
      unless image.width >= MINIMUM_WIDTH && image.height >= MINIMUM_HEIGHT
        return ServiceResult.failure(error: :invalid_minecraft_skin_dimensions)
      end

      ServiceResult.success(
        avatar: derivative(image.crop(8, 8, 8, 8), scale: 16),
        bust: derivative(image.crop(0, 0, 32, 32), scale: 8),
        full: derivative(image, scale: 8)
      )
    rescue Vips::Error
      ServiceResult.failure(error: :skin_derivative_generation_failed)
    end

    private

    def derivative(image, scale:)
      payload = image.resize(scale, kernel: :nearest).write_to_buffer(".png")
      {
        payload: payload,
        content_type: "image/png",
        width: image.width * scale,
        height: image.height * scale,
        sha256: Digest::SHA256.hexdigest(payload)
      }
    end
  end
end
