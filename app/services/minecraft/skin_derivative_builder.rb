# frozen_string_literal: true

require "digest"
require "vips"

module Minecraft
  class SkinDerivativeBuilder < ApplicationService
    MINIMUM_WIDTH = 64
    MINIMUM_HEIGHT = 32
    BUST_CANVAS_SIZE = 32
    BUST_SCALE = 8

    HEAD_FRONT = [ 8, 8, 8, 8 ].freeze
    HEAD_OVERLAY_FRONT = [ 40, 8, 8, 8 ].freeze
    TORSO_FRONT = [ 20, 20, 8, 12 ].freeze
    TORSO_OVERLAY_FRONT = [ 20, 36, 8, 12 ].freeze
    RIGHT_ARM_FRONT = [ 44, 20, 4, 12 ].freeze
    RIGHT_ARM_OVERLAY_FRONT = [ 44, 36, 4, 12 ].freeze
    LEFT_ARM_FRONT = [ 36, 52, 4, 12 ].freeze
    LEFT_ARM_OVERLAY_FRONT = [ 52, 52, 4, 12 ].freeze

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
        avatar: derivative(image.crop(*HEAD_FRONT), scale: 16),
        bust: derivative(build_bust(image), scale: BUST_SCALE),
        full: derivative(image, scale: 8)
      )
    rescue Vips::Error
      ServiceResult.failure(error: :skin_derivative_generation_failed)
    end

    private

    def build_bust(image)
      head = layered_part(image, HEAD_FRONT, HEAD_OVERLAY_FRONT)
      torso = layered_part(image, TORSO_FRONT, modern_skin?(image) ? TORSO_OVERLAY_FRONT : nil)
      right_arm = layered_part(
        image,
        RIGHT_ARM_FRONT,
        modern_skin?(image) ? RIGHT_ARM_OVERLAY_FRONT : nil
      )
      left_arm = if modern_skin?(image)
        layered_part(image, LEFT_ARM_FRONT, LEFT_ARM_OVERLAY_FRONT)
      else
        # Legacy 64 x 32 skins expose only the right limb texture. Minecraft
        # mirrors that texture for the left arm, so preserve the same contract.
        right_arm.flip(:horizontal)
      end

      body = Vips::Image.arrayjoin([ right_arm, torso, left_arm ], across: 3)
      bust = body.embed(0, 8, 16, 20, extend: :background, background: transparent)
      bust = bust.insert(head, 4, 0)
      bust.embed(8, 6, BUST_CANVAS_SIZE, BUST_CANVAS_SIZE,
        extend: :background, background: transparent)
    end

    def layered_part(image, base_region, overlay_region)
      base = with_alpha(image.crop(*base_region))
      return base unless overlay_region

      base.composite2(with_alpha(image.crop(*overlay_region)), :over)
    end

    def with_alpha(image)
      image.has_alpha? ? image : image.add_alpha
    end

    def modern_skin?(image)
      image.height >= 64
    end

    def transparent
      [ 0, 0, 0, 0 ]
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
