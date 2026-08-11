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
      assert_equal avatar, result.value.fetch(:avatar).fetch(:payload)
    end
  end
end
