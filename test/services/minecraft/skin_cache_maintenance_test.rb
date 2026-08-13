# frozen_string_literal: true

require "test_helper"
require "chunky_png"

module Minecraft
  class SkinCacheMaintenanceTest < ActiveSupport::TestCase
    test "selected refresh accepts a bounded identity list" do
      actor = create_user(account_type: :admin)

      assert_enqueued_with(job: Minecraft::RefreshAllSkinsJob) do
        result = Minecraft::RequestAllSkinRefreshes.call(
          actor: actor,
          request_id: "selected-refresh",
          scope: "selected",
          identity_ids: [ 9, "12", 9 ]
        )
        assert_predicate result, :success?, result.error
      end

      arguments = enqueued_jobs.last.fetch(:args).find { |entry| entry.is_a?(Hash) }
      assert_equal "selected", arguments.fetch("scope")
      assert_equal [ 9, 12 ], arguments.fetch("identity_ids")
    end

    test "manual task schema normalizes lists and rejects partial values" do
      entry = Operations::ManualTaskCatalog.entry("minecraft.skin.refresh_selected")
      normalized = Operations::ManualTaskCatalog.normalize_arguments(
        entry,
        identity_ids: "12, 42 81"
      )
      assert_equal [ 12, 42, 81 ], normalized.fetch("identity_ids")

      assert_raises(Operations::ManualTaskCatalog::InvalidTask) do
        Operations::ManualTaskCatalog.normalize_arguments(
          entry,
          identity_ids: "12, nope"
        )
      end
    end

    test "diagnostics report cache and primary integrity without exposing account ids" do
      user = create_user
      profile = Minecraft::PlayerProfile.create!
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Diagnostics",
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(
        user: user,
        player_profile: profile,
        linked_at: Time.current
      )

      cache = Minecraft::SkinCacheDiagnostics.call(kind: "cache_files")
      primary = Minecraft::SkinCacheDiagnostics.call(kind: "primary_accounts")

      assert_predicate cache, :success?, cache.error
      assert_operator cache.value.fetch(:incomplete), :>=, 1
      assert_predicate primary, :success?, primary.error
      assert_equal 0, primary.value.fetch(:invalid_primary_users)
      refute_match(/user_id|player_profile_id/, cache.value.to_json)
      refute_match(/user_id|player_profile_id/, primary.value.to_json)
    end

    test "derivative rebuild uses only the locally attached texture" do
      actor = create_user(account_type: :admin)
      user = create_user
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Derivative",
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(
        user: user,
        player_profile: profile,
        linked_at: Time.current
      )
      payload = ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color::WHITE).to_blob
      identity.skin_texture_file.attach(
        io: StringIO.new(payload),
        filename: "skin.png",
        content_type: "image/png"
      )

      result = Minecraft::RebuildSkinDerivatives.call(actor: actor)

      assert_predicate result, :success?, result.error
      identity.reload
      assert identity.skin_avatar_file.attached?
      assert identity.skin_bust_file.attached?
      assert identity.skin_full_file.attached?
      assert AuditLog.exists?(
        action: "minecraft.skin_derivatives_rebuilt",
        resource_id: identity.id
      )
    end

    test "fresh identities with an incomplete derivative set remain due for repair" do
      user = create_user
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "IncompleteDerivative",
        identity_type: "java",
        valid_from: Time.current,
        skin_cached_at: Time.current
      )
      Minecraft::IdentityLink.create!(
        user: user,
        player_profile: profile,
        linked_at: Time.current
      )
      payload = ChunkyPNG::Image.new(64, 64, ChunkyPNG::Color::WHITE).to_blob
      %i[skin_texture_file skin_avatar_file skin_full_file].each do |attachment_name|
        identity.public_send(attachment_name).attach(
          io: StringIO.new(payload),
          filename: "#{attachment_name}.png",
          content_type: "image/png"
        )
      end

      assert_includes Minecraft::PlayerIdentity.skin_cache_due(at: Time.current), identity

      identity.skin_bust_file.attach(
        io: StringIO.new(payload),
        filename: "skin_bust_file.png",
        content_type: "image/png"
      )

      refute_includes Minecraft::PlayerIdentity.skin_cache_due(at: Time.current), identity
    end
  end
end
