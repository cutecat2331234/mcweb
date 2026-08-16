# frozen_string_literal: true

require "test_helper"

module Minecraft
  class PlayerProfileTest < ActiveSupport::TestCase
    test "active identity uses a preloaded association without another query" do
      profile = Minecraft::PlayerProfile.create!
      active_java = create_identity(profile:, platform: "java", username: "CurrentJava")
      create_identity(profile:, platform: "bedrock", username: "CurrentBedrock")
      create_identity(
        profile:,
        platform: "java",
        username: "OldJava",
        superseded_at: 1.hour.ago
      )
      profile = Minecraft::PlayerProfile.includes(:player_identities).find(profile.id)

      queries = []
      subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
        queries << payload.fetch(:sql) unless payload[:name] == "SCHEMA" || payload[:cached]
      end
      result = ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        profile.active_identity
      end

      assert_equal active_java.id, result.id
      assert_empty queries
    end

    test "active identity keeps the scoped query fallback when identities are not loaded" do
      profile = Minecraft::PlayerProfile.create!
      active_java = create_identity(profile:, platform: "java", username: "CurrentJava")
      create_identity(
        profile:,
        platform: "java",
        username: "OldJava",
        superseded_at: 1.hour.ago
      )
      profile = Minecraft::PlayerProfile.find(profile.id)

      refute_predicate profile.association(:player_identities), :loaded?
      assert_equal active_java.id, profile.active_identity.id
    end

    private

    def create_identity(profile:, platform:, username:, superseded_at: nil)
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform:,
        external_uuid: SecureRandom.uuid,
        username:,
        identity_type: platform,
        valid_from: 1.day.ago,
        superseded_at:
      )
    end
  end
end
