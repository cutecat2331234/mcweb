# frozen_string_literal: true

require "test_helper"
require "chunky_png"
require "digest"

module Minecraft
  class AccountAndSkinCacheTest < ActiveSupport::TestCase
    setup do
      @user = create_user
      @actor = create_user(account_type: :admin)
    end

    test "multiple bound accounts select only the first as primary" do
      first_profile, = create_bound_account(user: @user, username: "First")
      second_profile, = create_bound_account(user: @user, username: "Second")

      links = Minecraft::IdentityLink.active.where(user: @user).order(:id)
      assert_equal 2, links.count
      assert_predicate links.first, :primary_account?
      refute_predicate links.second, :primary_account?
      assert_equal first_profile, links.first.player_profile
      assert_equal second_profile, links.second.player_profile

      index = ActiveRecord::Base.connection.indexes(:minecraft_identity_links).find do |candidate|
        candidate.name == "idx_mc_identity_links_one_primary_per_user"
      end
      assert index&.unique
      assert_match(/primary_account/i, index.where)
      assert_match(/unlinked_at/i, index.where)
    end

    test "profile presence follows the explicit primary account" do
      first_profile, = create_bound_account(user: @user, username: "First")
      second_profile, = create_bound_account(user: @user, username: "Second")
      second_link = Minecraft::IdentityLink.active.find_by!(
        user: @user,
        player_profile: second_profile
      )
      Minecraft::SetPrimaryAccount.call(
        user: @user,
        identity_link: second_link,
        actor: @actor,
        request_id: SecureRandom.uuid
      )
      server = Minecraft::Server.create!(
        name: "Presence Server",
        public_id: "srv_presence_#{SecureRandom.hex(4)}",
        connector_secret: SecureRandom.hex(32)
      )
      Minecraft::PlayerSession.create!(
        player_profile: first_profile,
        server: server,
        username: "First",
        joined_at: Time.current
      )

      secondary_only = Minecraft::IngameStatusForUser.call(user: @user)
      assert_predicate secondary_only, :success?
      refute secondary_only.value.fetch(:ingame_online)

      Minecraft::PlayerSession.create!(
        player_profile: second_profile,
        server: server,
        username: "Second",
        joined_at: Time.current
      )
      primary_online = Minecraft::IngameStatusForUser.call(user: @user)
      assert_predicate primary_online, :success?
      assert primary_online.value.fetch(:ingame_online)
      assert_equal server.public_id, primary_online.value.fetch(:ingame_server_id)
    end

    test "skin refresh stores sanitized PNGs locally and idempotent replay does no remote work" do
      profile, identity = create_bound_account(user: @user, username: "Cached")
      texture = texture_data(color: ChunkyPNG::Color.rgb(10, 20, 30))
      result = refresh_service(
        identity: identity,
        request_key: "manual-refresh-1",
        skin_data: texture
      ).call
      assert_predicate result, :success?, result.error
      assert result.value.fetch(:changed)

      identity.reload
      assert_predicate identity, :skin_cached?
      assert_equal texture.fetch(:sha256), identity.skin_texture_sha256
      assert_equal texture.fetch(:payload), identity.skin_texture_file.download
      assert_equal 1, identity.skin_cache_version
      assert AuditLog.exists?(
        action: "minecraft.skin_cache_refreshed",
        resource_type: "Minecraft::PlayerIdentity",
        resource_id: identity.id
      )

      replay = Minecraft::RefreshSkin.new(
        player_identity: identity,
        actor: @actor,
        trigger: "manual",
        idempotency_key: "manual-refresh-1"
      )
      replay.define_singleton_method(:fetch_mojang_textures) do |_uuid|
        raise "remote lookup must not replay"
      end
      replay_result = replay.call

      assert_predicate replay_result, :success?, replay_result.error
      assert replay_result.value.fetch(:replayed)
      assert_equal profile.public_id, replay_result.value.fetch(:player_id)
      assert_equal 1, Minecraft::SkinRefreshRequest.where(player_identity: identity).count
    end

    test "failed refresh retains the previous cache and records only a safe error code" do
      _, identity = create_bound_account(user: @user, username: "Retained")
      initial = refresh_service(
        identity: identity,
        request_key: "initial-cache",
        skin_data: texture_data(color: ChunkyPNG::Color::WHITE)
      ).call
      assert_predicate initial, :success?, initial.error

      identity.reload
      previous_blob_id = identity.skin_texture_file.blob.id
      previous_cached_at = identity.skin_cached_at
      previous_digest = identity.skin_texture_sha256

      failure = Minecraft::RefreshSkin.new(
        player_identity: identity,
        actor: @actor,
        trigger: "manual",
        idempotency_key: "failed-refresh"
      )
      failure.define_singleton_method(:fetch_mojang_textures) do |_uuid|
        {
          texture_url: "https://textures.minecraft.net/texture/def456",
          skin_model: "classic",
          cape_texture_url: nil
        }
      end
      failure.define_singleton_method(:download_texture) do |_url|
        ServiceResult.failure(error: :texture_fetch_failed)
      end

      result = failure.call
      assert_predicate result, :failure?
      assert result.value.fetch(:previous_cache_retained)

      identity.reload
      assert_equal previous_blob_id, identity.skin_texture_file.blob.id
      assert_equal previous_cached_at, identity.skin_cached_at
      assert_equal previous_digest, identity.skin_texture_sha256
      assert_equal "texture_fetch_failed", identity.skin_refresh_error_code

      audit = AuditLog.find_by!(
        action: "minecraft.skin_cache_refresh_failed",
        resource_type: "Minecraft::PlayerIdentity",
        resource_id: identity.id
      )
      assert_equal "texture_fetch_failed", audit.metadata.fetch("error_code")
      refute_includes audit.attributes.to_json, "textures.minecraft.net"
    end

    test "manual refresh persists only a digest and enqueues no raw request identifier" do
      _, identity = create_bound_account(user: @user, username: "PrivateRequest")
      raw_request_id = "do-not-persist-this-opaque-request"

      assert_enqueued_with(job: Minecraft::RefreshSkinJob) do
        result = Minecraft::RequestSkinRefresh.call(
          player_identity: identity,
          actor: @actor,
          request_id: raw_request_id,
          trigger: "manual"
        )
        assert_predicate result, :success?, result.error
      end

      request = Minecraft::SkinRefreshRequest.find_by!(player_identity: identity)
      assert_equal Digest::SHA256.hexdigest(raw_request_id), request.idempotency_key_digest
      refute_includes request.attributes.to_json, raw_request_id
      refute_includes enqueued_jobs.last.fetch(:args).to_json, raw_request_id
    end

    test "scheduled refresh queues only due bound accounts on the daily default" do
      _, due_identity = create_bound_account(user: @user, username: "Due")
      _, fresh_identity = create_bound_account(user: @user, username: "Fresh")
      fresh_identity.update!(skin_cached_at: 23.hours.ago)
      unbound_profile = Minecraft::PlayerProfile.create!
      unbound_identity = Minecraft::PlayerIdentity.create!(
        player_profile: unbound_profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: "Unbound",
        identity_type: "java",
        valid_from: Time.current
      )

      assert_enqueued_jobs 1, only: Minecraft::RefreshSkinJob do
        Minecraft::RefreshAllSkinsJob.perform_now
      end

      queued_args = enqueued_jobs.find { |job| job[:job] == Minecraft::RefreshSkinJob }.fetch(:args)
      keyword_args = queued_args.find { |entry| entry.is_a?(Hash) }
      assert_equal due_identity.id, keyword_args.fetch("identity_id")
      refute_equal fresh_identity.id, keyword_args.fetch("identity_id")
      refute_equal unbound_identity.id, keyword_args.fetch("identity_id")
      assert_equal 24.hours, Minecraft::PlayerIdentity::DEFAULT_SKIN_REFRESH_INTERVAL
    end

    test "texture downloader permits only canonical Minecraft texture hosts" do
      assert_equal(
        "https://textures.minecraft.net/texture/abc123",
        Minecraft::TextureCacheDownloader.canonical_url(
          "http://textures.minecraft.net/texture/abc123"
        )
      )
      assert Minecraft::TextureCacheDownloader.allowed_url?(
        "https://textures.minecraft.net/texture/abc123"
      )
      refute Minecraft::TextureCacheDownloader.allowed_url?(
        "https://textures.minecraft.net.evil.example/texture/abc123"
      )
      refute Minecraft::TextureCacheDownloader.allowed_url?(
        "http://169.254.169.254/latest/meta-data/"
      )
    end

    private

    def create_bound_account(user:, username:)
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(
        player_profile: profile,
        user: user,
        linked_at: Time.current
      )
      [ profile, identity ]
    end

    def refresh_service(identity:, request_key:, skin_data:)
      service = Minecraft::RefreshSkin.new(
        player_identity: identity,
        actor: @actor,
        trigger: "manual",
        idempotency_key: request_key
      )
      service.define_singleton_method(:fetch_mojang_textures) do |_uuid|
        {
          texture_url: "https://textures.minecraft.net/texture/abc123",
          skin_model: "slim",
          cape_texture_url: nil
        }
      end
      service.define_singleton_method(:download_texture) do |_url|
        ServiceResult.success(skin_data)
      end
      service
    end

    def texture_data(color:)
      payload = ChunkyPNG::Image.new(64, 64, color).to_blob
      {
        payload: payload,
        content_type: "image/png",
        width: 64,
        height: 64,
        sha256: Digest::SHA256.hexdigest(payload)
      }
    end
  end
end
