# frozen_string_literal: true

require "test_helper"
require "chunky_png"

module Minecraft
  class CachedSkinsTest < ActionDispatch::IntegrationTest
    test "bound cached skin variants expose only a controlled local endpoint" do
      user = create_user
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "LocalCache",
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(user: user, player_profile: profile, linked_at: Time.current)
      payload = ChunkyPNG::Image.new(16, 16, ChunkyPNG::Color::WHITE).to_blob
      identity.skin_avatar_file.attach(
        io: StringIO.new(payload),
        filename: "avatar.png",
        content_type: "image/png"
      )

      get minecraft_cached_skin_path(identity, variant: "avatar")

      assert_response :redirect
      assert_match(%r{\A/rails/active_storage/}, response.location.delete_prefix("http://www.example.com"))
      refute_match(%r{https?://(?:textures\.minecraft\.net|sessionserver\.mojang\.com)}, response.location)
      assert_match(/public/, response.headers.fetch("Cache-Control"))
    end

    test "missing and unbound cache variants never disclose an upstream URL" do
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Unbound",
        identity_type: "java",
        valid_from: Time.current
      )

      get minecraft_cached_skin_path(identity, variant: "avatar")
      assert_redirected_to "/minecraft/default-skin-avatar.png"
      refute_match(/textures\.minecraft\.net|sessionserver\.mojang\.com/, response.location)

      get minecraft_cached_skin_path(identity, variant: "skin")
      assert_response :not_found

      get "/minecraft/cached-skins/#{identity.id}/unsupported"
      assert_response :not_found
    end
  end
end
