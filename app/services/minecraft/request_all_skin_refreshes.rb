# frozen_string_literal: true

require "digest"

module Minecraft
  class RequestAllSkinRefreshes < ApplicationService
    SCOPES = %w[all due selected missing failed].freeze

    def initialize(actor:, request_id:, force: true, scope: nil, identity_ids: nil)
      @actor = actor
      @request_id = request_id.to_s
      @force = force
      @scope = (scope.presence || (force ? "all" : "due")).to_s
      @identity_ids = Array(identity_ids).map { |value| Integer(value, exception: false) }.compact.uniq
    end

    def call
      return ServiceResult.failure(error: :skin_refresh_actor_required) unless @actor
      return ServiceResult.failure(error: :skin_refresh_request_id_required) if @request_id.blank?
      return ServiceResult.failure(error: :skin_refresh_scope_invalid) unless @scope.in?(SCOPES)
      return ServiceResult.failure(error: :skin_refresh_selection_required) if @scope == "selected" && @identity_ids.empty?
      return ServiceResult.failure(error: :skin_refresh_selection_too_large) if @identity_ids.length > 200

      Minecraft::RefreshAllSkinsJob.perform_later(
        actor_id: @actor.id,
        trigger: "bulk_manual",
        request_key_digest: Digest::SHA256.hexdigest(@request_id),
        force: @force,
        scope: @scope,
        identity_ids: @identity_ids
      )

      ServiceResult.success(enqueued: true)
    end
  end
end
