# frozen_string_literal: true

require "digest"

module Minecraft
  class RequestSkinRefresh < ApplicationService
    ALLOWED_TRIGGERS = %w[manual link scheduled bulk_manual].freeze

    def initialize(player_identity:, actor: nil, request_id:, trigger: "manual", force: true)
      @player_identity = player_identity
      @actor = actor
      @request_id = request_id.to_s
      @trigger = trigger.to_s
      @force = force
    end

    def call
      unless @player_identity && @player_identity.superseded_at.nil?
        return ServiceResult.failure(error: :minecraft_identity_unavailable)
      end
      return ServiceResult.failure(error: :skin_refresh_request_id_required) if @request_id.blank?
      return ServiceResult.failure(error: :invalid_skin_refresh_trigger) unless @trigger.in?(ALLOWED_TRIGGERS)
      return ServiceResult.failure(error: :skin_refresh_actor_required) if @trigger.in?(%w[manual bulk_manual]) && !@actor

      digest = Digest::SHA256.hexdigest(@request_id)
      request = Minecraft::SkinRefreshRequest.find_or_create_by!(
        player_identity: @player_identity,
        idempotency_key_digest: digest
      ) do |record|
        record.requested_by = @actor
        record.trigger = @trigger
      end

      unless request.terminal?
        Minecraft::RefreshSkinJob.perform_later(
          nil,
          identity_id: @player_identity.id,
          actor_id: @actor&.id,
          trigger: @trigger,
          idempotency_key_digest: digest,
          force: @force
        )
      end

      ServiceResult.success(
        request: request,
        replayed: request.terminal?
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
