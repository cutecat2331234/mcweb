# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "stringio"

module Minecraft
  class RefreshSkin < ApplicationService
    MOJANG_PROFILE_URL = "https://sessionserver.mojang.com/session/minecraft/profile/%s"
    MAX_PROFILE_BYTES = 256.kilobytes
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 10

    class ResponseTooLarge < StandardError; end

    def initialize(
      uuid: nil,
      platform: "java",
      player_identity: nil,
      actor: nil,
      trigger: "direct",
      idempotency_key: nil,
      idempotency_key_digest: nil,
      force: true
    )
      @uuid = uuid.to_s.delete("-")
      @platform = platform
      @player_identity = player_identity
      @actor = actor
      @trigger = trigger.to_s.first(40).presence || "direct"
      @idempotency_key = idempotency_key
      @idempotency_key_digest = idempotency_key_digest
      @force = force
    end

    def call
      identity = find_identity
      return ServiceResult.failure(error: :identity_not_found) unless identity

      if developer_mode_simulation?
        return ServiceResult.success(
          player_id: identity.player_profile.public_id,
          simulated: true,
          skin_cached: identity.skin_cached?,
          skin_model: identity.skin_model
        )
      end

      request = refresh_request_for(identity)
      claim = claim_request(request)
      return replay_result(request, identity) if claim == :terminal
      return ServiceResult.failure(error: :skin_refresh_in_progress) if claim == :busy

      unless @force || identity.skin_cache_stale?
        return persist_fresh_cache_hit(identity:, request:)
      end

      profile_data = fetch_mojang_textures(identity.external_uuid)
      return persist_failure(identity:, request:, error_code: :textures_not_found) unless profile_data

      skin_result = download_texture(profile_data.fetch(:texture_url))
      unless skin_result.success?
        return persist_failure(
          identity:,
          request:,
          error_code: normalized_error_code(skin_result.error, fallback: :texture_fetch_failed)
        )
      end

      cape_result = nil
      if profile_data[:cape_texture_url].present?
        cape_result = download_texture(profile_data[:cape_texture_url])
        unless cape_result.success?
          return persist_failure(
            identity:,
            request:,
            error_code: normalized_error_code(cape_result.error, fallback: :cape_texture_fetch_failed)
          )
        end
      end

      persist_downloaded_textures(
        identity:,
        request:,
        profile_data:,
        skin_data: skin_result.value,
        cape_data: cape_result&.value
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    rescue StandardError => e
      Rails.logger.warn("[minecraft.skin_cache] refresh failed: #{e.class}")
      begin
        return persist_failure(
          identity: identity,
          request: request,
          error_code: :skin_refresh_failed
        ) if identity && request
      rescue StandardError => persistence_error
        Rails.logger.error("[minecraft.skin_cache] failure audit unavailable: #{persistence_error.class}")
      end
      ServiceResult.failure(error: :skin_refresh_failed)
    end

    private

    def developer_mode_simulation?
      Mcweb::DeveloperMode.enabled? &&
        Mcweb::DeveloperMode.integration(:remote_skin_lookup) == :simulate
    end

    def find_identity
      return @player_identity if @player_identity && @player_identity.superseded_at.nil?

      bare = @uuid.delete("-")
      PlayerIdentity.active
                    .where(platform: @platform)
                    .where("external_uuid = ? OR REPLACE(external_uuid, '-', '') = ?", @uuid, bare)
                    .first
    end

    def refresh_request_for(identity)
      digest = normalized_idempotency_digest
      Minecraft::SkinRefreshRequest.find_or_create_by!(
        player_identity: identity,
        idempotency_key_digest: digest
      ) do |record|
        record.requested_by = @actor
        record.trigger = @trigger
      end
    end

    def normalized_idempotency_digest
      candidate = @idempotency_key_digest.to_s.downcase
      return candidate if candidate.match?(/\A[0-9a-f]{64}\z/)

      raw_key = @idempotency_key.presence || SecureRandom.uuid
      Digest::SHA256.hexdigest(raw_key.to_s)
    end

    def claim_request(request)
      outcome = nil
      request.with_lock do
        if request.terminal?
          outcome = :terminal
        elsif request.running? && !request.stale_running?
          outcome = :busy
        else
          request.update!(status: "running", started_at: Time.current, completed_at: nil, error_code: nil)
          outcome = :claimed
        end
      end
      outcome
    end

    def replay_result(request, identity)
      value = {
        player_id: identity.player_profile.public_id,
        request_id: request.id,
        changed: request.cache_changed?,
        replayed: true
      }
      return ServiceResult.success(value) if request.succeeded?

      ServiceResult.failure(error: request.error_code.presence || :skin_refresh_failed, value: value)
    end

    def persist_fresh_cache_hit(identity:, request:)
      now = Time.current
      ActiveRecord::Base.transaction do
        identity.lock!
        request.lock!
        identity.update!(skin_refresh_attempted_at: now, skin_refresh_failed_at: nil, skin_refresh_error_code: nil)
        request.update!(status: "succeeded", cache_changed: false, completed_at: now, error_code: nil)
        audit_refresh(identity:, request:, action: "minecraft.skin_cache_refreshed", changed: false)
      end

      ServiceResult.success(
        player_id: identity.player_profile.public_id,
        request_id: request.id,
        changed: false,
        cache_hit: true
      )
    end

    def persist_downloaded_textures(identity:, request:, profile_data:, skin_data:, cape_data:)
      created_blobs = []
      now = Time.current
      changed = false
      derivatives_result = Minecraft::SkinDerivativeBuilder.call(
        payload: skin_data.fetch(:payload),
        model: profile_data[:skin_model]
      )
      unless derivatives_result.success?
        return persist_failure(
          identity:,
          request:,
          error_code: derivatives_result.error || :skin_derivative_generation_failed
        )
      end
      derivatives = derivatives_result.value

      ActiveRecord::Base.transaction do
        identity.lock!
        request.lock!

        skin_file_changed = !identity.skin_texture_file.attached? ||
          identity.skin_texture_sha256 != skin_data.fetch(:sha256)
        derivatives_missing = !identity.skin_avatar_file.attached? ||
          !identity.skin_bust_file.attached? ||
          !identity.skin_full_file.attached?
        derivative_files_changed = skin_file_changed || derivatives_missing
        cape_file_changed = cape_changed?(identity, cape_data)
        metadata_changed = identity.skin_texture_url != profile_data[:texture_url] ||
          identity.cape_texture_url != profile_data[:cape_texture_url] ||
          identity.skin_model != profile_data[:skin_model]
        changed = skin_file_changed || derivative_files_changed || cape_file_changed || metadata_changed

        if skin_file_changed
          blob = create_texture_blob(
            identity:,
            texture_kind: "skin",
            texture_data: skin_data
          )
          created_blobs << blob
          identity.skin_texture_file.attach(blob)

        end

        if derivative_files_changed
          {
            "avatar" => [ identity.skin_avatar_file, derivatives.fetch(:avatar) ],
            "bust" => [ identity.skin_bust_file, derivatives.fetch(:bust) ],
            "full" => [ identity.skin_full_file, derivatives.fetch(:full) ]
          }.each do |texture_kind, (attachment, texture_data)|
            derivative_blob = create_texture_blob(
              identity:,
              texture_kind:,
              texture_data:
            )
            created_blobs << derivative_blob
            attachment.attach(derivative_blob)
          end
        end

        if cape_data
          if cape_file_changed
            blob = create_texture_blob(
              identity:,
              texture_kind: "cape",
              texture_data: cape_data
            )
            created_blobs << blob
            identity.cape_texture_file.attach(blob)
          end
        elsif identity.cape_texture_file.attached?
          identity.cape_texture_file.detach
        end

        identity.update!(
          skin_texture_url: profile_data[:texture_url],
          skin_model: profile_data[:skin_model],
          cape_texture_url: profile_data[:cape_texture_url],
          skin_cached_at: now,
          skin_refresh_attempted_at: now,
          skin_refresh_failed_at: nil,
          skin_refresh_error_code: nil,
          skin_texture_sha256: skin_data.fetch(:sha256),
          cape_texture_sha256: cape_data&.fetch(:sha256),
          skin_cache_version: identity.skin_cache_version + (changed ? 1 : 0)
        )
        sync_legacy_identity(identity)

        request.update!(status: "succeeded", cache_changed: changed, completed_at: now, error_code: nil)
        audit_refresh(identity:, request:, action: "minecraft.skin_cache_refreshed", changed: changed)
      end

      ServiceResult.success(
        player_id: identity.player_profile.public_id,
        request_id: request.id,
        changed: changed,
        skin_cached: identity.reload.skin_cached?
      )
    rescue StandardError
      created_blobs.each do |blob|
        blob.purge unless blob.attachments.exists?
      rescue StandardError
        nil
      end
      raise
    end

    def cape_changed?(identity, cape_data)
      if cape_data
        !identity.cape_texture_file.attached? || identity.cape_texture_sha256 != cape_data.fetch(:sha256)
      else
        identity.cape_texture_file.attached? || identity.cape_texture_sha256.present?
      end
    end

    def create_texture_blob(identity:, texture_kind:, texture_data:)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(texture_data.fetch(:payload)),
        filename: "minecraft-#{identity.id}-#{texture_kind}-#{texture_data.fetch(:sha256).first(12)}.png",
        content_type: "image/png",
        identify: false,
        metadata: {
          "minecraft_texture_kind" => texture_kind,
          "sha256" => texture_data.fetch(:sha256),
          "width" => texture_data[:width],
          "height" => texture_data[:height]
        }.compact
      )
    end

    def persist_failure(identity:, request:, error_code:)
      return ServiceResult.failure(error: error_code) unless identity && request

      safe_code = normalized_error_code(error_code, fallback: :skin_refresh_failed).to_s
      now = Time.current
      ActiveRecord::Base.transaction do
        identity.lock!
        request.lock!
        identity.update!(
          skin_refresh_attempted_at: now,
          skin_refresh_failed_at: now,
          skin_refresh_error_code: safe_code
        )
        request.update!(status: "failed", error_code: safe_code, cache_changed: false, completed_at: now)
        audit_refresh(
          identity:,
          request:,
          action: "minecraft.skin_cache_refresh_failed",
          changed: false,
          error_code: safe_code
        )
      end

      ServiceResult.failure(
        error: safe_code,
        value: {
          player_id: identity.player_profile.public_id,
          request_id: request.id,
          previous_cache_retained: identity.skin_cached?
        }
      )
    end

    def audit_refresh(identity:, request:, action:, changed:, error_code: nil)
      Administration::AuditLogger.call(
        actor: request.requested_by,
        action: action,
        resource: identity,
        request_id: "minecraft-skin-refresh-#{request.id}",
        metadata: {
          trigger: request.trigger,
          changed: changed,
          error_code: error_code,
          cache_version: identity.skin_cache_version
        }.compact
      )
    end

    def download_texture(url)
      Minecraft::TextureCacheDownloader.call(url: url)
    end

    def fetch_mojang_textures(uuid)
      url = format(MOJANG_PROFILE_URL, uuid.delete("-"))
      payload = fetch_profile_payload(URI(url))
      return nil unless payload

      body = JSON.parse(payload)
      property = Array(body["properties"]).find { |entry| entry["name"] == "textures" }
      return nil unless property

      decoded = JSON.parse(Base64.strict_decode64(property.fetch("value")))
      skin_url = Minecraft::TextureCacheDownloader.canonical_url(decoded.dig("textures", "SKIN", "url"))
      return nil unless skin_url

      cape_url = Minecraft::TextureCacheDownloader.canonical_url(decoded.dig("textures", "CAPE", "url"))
      metadata = decoded.dig("textures", "SKIN", "metadata") || {}
      {
        texture_url: skin_url,
        skin_model: metadata["model"].presence || "classic",
        cape_texture_url: cape_url
      }
    rescue JSON::ParserError, ArgumentError, KeyError
      nil
    end

    def fetch_profile_payload(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
        return nil unless response.is_a?(Net::HTTPSuccess)
        raise ResponseTooLarge if response.content_length.to_i > MAX_PROFILE_BYTES

        payload = +"".b
        response.read_body do |chunk|
          payload << chunk
          raise ResponseTooLarge if payload.bytesize > MAX_PROFILE_BYTES
        end
        payload
      end
    rescue ResponseTooLarge, StandardError
      nil
    end

    def sync_legacy_identity(identity)
      legacy = Identity.find_by(player_profile: identity.player_profile)
      return unless legacy

      legacy.update!(
        skin_texture_url: identity.skin_texture_url,
        skin_model: identity.skin_model,
        cape_texture_url: identity.cape_texture_url
      )
    end

    def normalized_error_code(value, fallback:)
      code = value.to_s
      return code.to_sym if code.match?(/\A[a-z][a-z0-9_]{0,99}\z/)

      fallback
    end
  end
end
