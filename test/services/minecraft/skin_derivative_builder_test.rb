# frozen_string_literal: true

require "test_helper"

module Minecraft
  class SkinDerivativeBuilderTest < ActiveSupport::TestCase
    test "bust composes modern skin front layers on a transparent canvas" do
      skin = transparent_image(64, 64)
      skin = paint(skin, SkinDerivativeBuilder::HEAD_FRONT, [ 180, 10, 20, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::HEAD_OVERLAY_FRONT, [ 10, 190, 20, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::TORSO_FRONT, [ 10, 20, 200, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::TORSO_OVERLAY_FRONT, [ 210, 200, 20, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_FRONT, [ 160, 20, 170, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_OVERLAY_FRONT, [ 20, 180, 190, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::LEFT_ARM_FRONT, [ 220, 100, 20, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::LEFT_ARM_OVERLAY_FRONT, [ 230, 230, 230, 255 ])

      result = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"))

      assert result.success?
      derivative = result.value.fetch(:bust)
      assert_equal "image/png", derivative.fetch(:content_type)
      assert_equal 256, derivative.fetch(:width)
      assert_equal 256, derivative.fetch(:height)
      assert_equal Digest::SHA256.hexdigest(derivative.fetch(:payload)), derivative.fetch(:sha256)

      bust = Vips::Image.new_from_buffer(derivative.fetch(:payload), "")
      assert_pixel bust, 0, 0, [ 0, 0, 0, 0 ]
      assert_pixel bust, 12, 6, [ 10, 190, 20, 255 ]
      assert_pixel bust, 8, 14, [ 20, 180, 190, 255 ]
      assert_pixel bust, 12, 14, [ 210, 200, 20, 255 ]
      assert_pixel bust, 20, 14, [ 230, 230, 230, 255 ]
    end

    test "bust mirrors the available arm texture for legacy 64 x 32 skins" do
      skin = transparent_image(64, 32)
      skin = paint(skin, SkinDerivativeBuilder::HEAD_FRONT, [ 150, 80, 40, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::TORSO_FRONT, [ 30, 90, 170, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_FRONT, [ 20, 40, 200, 255 ])
      skin = paint(skin, [ 44, 20, 1, 12 ], [ 240, 30, 20, 255 ])

      result = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"))

      assert result.success?
      bust = Vips::Image.new_from_buffer(result.value.fetch(:bust).fetch(:payload), "")
      assert_pixel bust, 8, 14, [ 240, 30, 20, 255 ]
      assert_pixel bust, 20, 14, [ 20, 40, 200, 255 ]
      assert_pixel bust, 23, 14, [ 240, 30, 20, 255 ]
    end

    private

    def transparent_image(width, height)
      Vips::Image.black(width, height, bands: 4)
    end

    def paint(image, region, rgba)
      x, y, width, height = region
      color = Vips::Image.black(width, height, bands: 4).new_from_image(rgba)
      image.insert(color, x, y)
    end

    def assert_pixel(image, source_x, source_y, expected)
      scale = SkinDerivativeBuilder::BUST_SCALE
      actual = image.getpoint((source_x * scale) + (scale / 2), (source_y * scale) + (scale / 2))
      assert_equal expected, actual.map(&:round)
    end
  end
end
