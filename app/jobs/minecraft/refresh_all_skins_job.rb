# frozen_string_literal: true

require "digest"

module Minecraft
  class RefreshAllSkinsJob < ApplicationJob
    queue_as :minecraft

    def perform(
      actor_id: nil,
      trigger: "scheduled",
      request_key_digest: nil,
      force: false,
      scope: nil,
      identity_ids: nil
    )
      actor = User.find_by(id: actor_id) if actor_id
      batch_digest = normalized_batch_digest(request_key_digest, trigger)
      selection = normalized_scope(scope, force)
      identities = selected_scope(selection, identity_ids)

      identities.find_each do |identity|
        next if selection == "missing" && identity.skin_cached?

        identity_digest = Digest::SHA256.hexdigest("#{batch_digest}:#{identity.id}")
        Minecraft::RefreshSkinJob.perform_later(
          nil,
          identity_id: identity.id,
          actor_id: actor&.id,
          trigger: trigger,
          idempotency_key_digest: identity_digest,
          force: force
        )
      end
    end

    private

    def normalized_scope(value, force)
      candidate = value.to_s
      return candidate if candidate.in?(Minecraft::RequestAllSkinRefreshes::SCOPES)

      force ? "all" : "due"
    end

    def selected_scope(selection, identity_ids)
      relation = Minecraft::PlayerIdentity.active.bound
      case selection
      when "due"
        relation.skin_cache_due
      when "selected"
        relation.where(id: Array(identity_ids).filter_map { |value| Integer(value, exception: false) }.uniq.first(200))
      when "failed"
        relation.where.not(skin_refresh_failed_at: nil).where("skin_refresh_failed_at >= ?", 7.days.ago)
      else
        relation
      end
    end

    def normalized_batch_digest(value, trigger)
      candidate = value.to_s.downcase
      return candidate if candidate.match?(/\A[0-9a-f]{64}\z/)

      Digest::SHA256.hexdigest("#{trigger}:#{Time.current.utc.to_date.iso8601}")
    end
  end
end
