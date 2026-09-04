# frozen_string_literal: true

require "test_helper"

module Minecraft
  class DefaultSkinAssetTest < ActiveSupport::TestCase
    test "fallback avatar is a deterministic derivative of the bundled Minecraft skin" do
      source = Rails.root.join("public/minecraft/default-skin.png").binread
      avatar = Rails.root.join("public/minecraft/default-skin-avatar.png").binread

      result = SkinDerivativeBuilder.call(payload: source)

      assert result.success?
      assert_equal "image/png", result.value.fetch(:avatar).fetch(:content_type)
      assert_equal 128, result.value.fetch(:avatar).fetch(:width)
      assert_equal 128, result.value.fetch(:avatar).fetch(:height)

      expected_image = Vips::Image.new_from_buffer(avatar, "")
      generated_image = Vips::Image.new_from_buffer(
        result.value.fetch(:avatar).fetch(:payload),
        ""
      )
      assert_equal expected_image.width, generated_image.width
      assert_equal expected_image.height, generated_image.height
      assert_equal expected_image.bands, generated_image.bands
      assert_equal expected_image.interpretation, generated_image.interpretation
      assert_equal expected_image.has_alpha?, generated_image.has_alpha?
      assert_equal expected_image.write_to_memory, generated_image.write_to_memory
    end
  end
end
