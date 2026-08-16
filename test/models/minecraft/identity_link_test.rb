# frozen_string_literal: true

require "test_helper"

module Minecraft
  class IdentityLinkTest < ActiveSupport::TestCase
    test "unlink remains a soft delete and advances the optimistic lock" do
      user = create_user
      link = create_bound_account(user: user, username: "SoftDelete")
      original_lock_version = link.lock_version

      link.unlink!

      assert_not_nil link.reload.unlinked_at
      assert_operator link.lock_version, :>, original_lock_version
      assert_not link.primary_account?
      assert Minecraft::PlayerProfile.exists?(link.player_profile_id)
    end

    private

    def create_bound_account(user:, username:)
      profile = Minecraft::PlayerProfile.create!
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(user: user, player_profile: profile, linked_at: Time.current)
    end
  end
end
