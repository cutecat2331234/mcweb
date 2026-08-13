# frozen_string_literal: true

require "digest"
require "vips"

module Minecraft
  class SkinDerivativeBuilder < ApplicationService
    MINIMUM_WIDTH = 64
    MINIMUM_HEIGHT = 32
    BUST_CANVAS_SIZE = IsometricSkinBustRenderer::CANVAS_SIZE
    BUST_SCALE = 1

    HEAD_FRONT = IsometricSkinBustRenderer::HEAD_FRONT
    HEAD_OVERLAY_FRONT = IsometricSkinBustRenderer::HEAD_OVERLAY_FRONT
    TORSO_FRONT = IsometricSkinBustRenderer::TORSO_FRONT
    TORSO_OVERLAY_FRONT = IsometricSkinBustRenderer::TORSO_OVERLAY_FRONT
    RIGHT_ARM_FRONT = IsometricSkinBustRenderer::RIGHT_ARM_FRONT
    RIGHT_ARM_OVERLAY_FRONT = IsometricSkinBustRenderer::RIGHT_ARM_OVERLAY_FRONT
    LEFT_ARM_FRONT = IsometricSkinBustRenderer::LEFT_ARM_FRONT
    LEFT_ARM_OVERLAY_FRONT = IsometricSkinBustRenderer::LEFT_ARM_OVERLAY_FRONT

    def initialize(payload:, model: nil)
      @payload = payload.to_s.b
      @model = model
    end

    def call
      # A single source image is cropped several times in different regions.
      # Sequential access can no longer seek back after the first derivative.
      image = Vips::Image.new_from_buffer(@payload, "")
      unless image.width >= MINIMUM_WIDTH && image.height >= MINIMUM_HEIGHT
        return ServiceResult.failure(error: :invalid_minecraft_skin_dimensions)
      end

      ServiceResult.success(
        avatar: derivative(image.crop(*HEAD_FRONT), scale: 16),
        bust: derivative(build_bust(image), scale: BUST_SCALE),
        full: derivative(image, scale: 8)
      )
    rescue Vips::Error
      ServiceResult.failure(error: :skin_derivative_generation_failed)
    end

    private

    def build_bust(image)
      IsometricSkinBustRenderer.call(image:, model: @model)
    end

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
