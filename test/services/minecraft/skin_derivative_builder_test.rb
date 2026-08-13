# frozen_string_literal: true

require "test_helper"

module Minecraft
  class SkinDerivativeBuilderTest < ActiveSupport::TestCase
    test "bust renders modern skin cuboids and overlays on a transparent canvas" do
      skin = transparent_image(64, 64)
      skin = paint(skin, SkinDerivativeBuilder::HEAD_FRONT, [ 180, 10, 20, 255 ])
      skin = paint(skin, [ 8, 0, 8, 8 ], [ 10, 100, 150, 255 ])
      skin = paint(skin, [ 0, 8, 8, 8 ], [ 100, 80, 60, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::TORSO_FRONT, [ 10, 20, 200, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_FRONT, [ 160, 20, 170, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::LEFT_ARM_FRONT, [ 220, 100, 20, 255 ])
      skin = paint(skin, [ 40, 8, 1, 1 ], [ 10, 190, 20, 255 ])
      skin = paint(skin, [ 20, 36, 1, 1 ], [ 210, 200, 20, 255 ])
      skin = paint(skin, [ 44, 36, 1, 1 ], [ 20, 180, 190, 255 ])
      skin = paint(skin, [ 52, 52, 1, 1 ], [ 230, 230, 230, 255 ])

      result = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"))

      assert result.success?
      derivative = result.value.fetch(:bust)
      assert_equal "image/png", derivative.fetch(:content_type)
      assert_equal 256, derivative.fetch(:width)
      assert_equal 256, derivative.fetch(:height)
      assert_equal Digest::SHA256.hexdigest(derivative.fetch(:payload)), derivative.fetch(:sha256)

      bust = Vips::Image.new_from_buffer(derivative.fetch(:payload), "")
      assert_pixel bust, 0, 0, [ 0, 0, 0, 0 ]
      assert_rgba_present bust, [ 180, 10, 20, 255 ]
      assert_rgba_present bust, [ 11, 108, 162, 255 ]
      assert_rgba_present bust, [ 78, 62, 47, 255 ]
      assert_rgba_present bust, [ 10, 20, 200, 255 ]
      assert_rgba_present bust, [ 160, 20, 170, 255 ]
      assert_rgba_present bust, [ 220, 100, 20, 255 ]
      assert_rgba_present bust, [ 10, 190, 20, 255 ]
      assert_rgba_present bust, [ 210, 200, 20, 255 ]
      assert_rgba_present bust, [ 20, 180, 190, 255 ]
      assert_rgba_present bust, [ 230, 230, 230, 255 ]
    end

    test "bust mirrors the available arm cuboid for legacy 64 x 32 skins" do
      skin = transparent_image(64, 32)
      skin = paint(skin, SkinDerivativeBuilder::HEAD_FRONT, [ 150, 80, 40, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::TORSO_FRONT, [ 30, 90, 170, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_FRONT, [ 20, 40, 200, 255 ])
      skin = paint(skin, [ 44, 20, 1, 12 ], [ 240, 30, 20, 255 ])

      result = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"))

      assert result.success?
      bust = Vips::Image.new_from_buffer(result.value.fetch(:bust).fetch(:payload), "")
      red_points = matching_points(bust, [ 240, 30, 20, 255 ])
      assert red_points.any? { |x, _y| x < 96 }, "expected the source stripe on the right arm"
      assert red_points.any? { |x, _y| x > 160 }, "expected a mirrored stripe on the left arm"
      assert_rgba_present bust, [ 20, 40, 200, 255 ]
    end

    test "bust honors the slim arm model" do
      skin = transparent_image(64, 64)
      skin = paint(skin, SkinDerivativeBuilder::RIGHT_ARM_FRONT, [ 80, 120, 200, 255 ])
      skin = paint(skin, SkinDerivativeBuilder::LEFT_ARM_FRONT, [ 80, 120, 200, 255 ])

      classic = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"), model: "classic")
      slim = SkinDerivativeBuilder.call(payload: skin.write_to_buffer(".png"), model: "slim")

      assert classic.success?
      assert slim.success?
      classic_bust = Vips::Image.new_from_buffer(classic.value.fetch(:bust).fetch(:payload), "")
      slim_bust = Vips::Image.new_from_buffer(slim.value.fetch(:bust).fetch(:payload), "")
      assert_operator opaque_width(slim_bust), :<, opaque_width(classic_bust)
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

    def assert_pixel(image, x, y, expected)
      actual = image.getpoint(x, y)
      assert_equal expected, actual.map(&:round)
    end

    def assert_rgba_present(image, expected)
      assert matching_points(image, expected).any?, "expected rendered image to contain #{expected.inspect}"
    end

    def matching_points(image, expected)
      pixels = image.write_to_memory.unpack("C*")
      points = []
      image.height.times do |y|
        image.width.times do |x|
          offset = ((y * image.width) + x) * image.bands
          points << [ x, y ] if pixels.slice(offset, 4) == expected
        end
      end
      points
    end

    def opaque_width(image)
      pixels = image.write_to_memory.unpack("C*")
      x_coordinates = []
      image.height.times do |y|
        image.width.times do |x|
          offset = ((y * image.width) + x) * image.bands
          x_coordinates << x if pixels.fetch(offset + 3).positive?
        end
      end
      x_coordinates.max - x_coordinates.min + 1
    end
  end
end
