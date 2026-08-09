# frozen_string_literal: true

require "digest"

module Minecraft
  class RefreshSkinJob < ApplicationJob
    queue_as :minecraft

    def perform(
      uuid = nil,
      platform: "java",
      identity_id: nil,
      actor_id: nil,
      trigger: "scheduled",
      idempotency_key_digest: nil,
      force: true
    )
      identity = identity_id ? Minecraft::PlayerIdentity.active.find_by(id: identity_id) : nil
      return unless identity || uuid.present?

      actor = User.find_by(id: actor_id) if actor_id
      digest = idempotency_key_digest.presence ||
        Digest::SHA256.hexdigest("minecraft-skin-job:#{job_id}")

      Minecraft::RefreshSkin.call(
        uuid: uuid,
        platform: platform,
        player_identity: identity,
        actor: actor,
        trigger: trigger,
        idempotency_key_digest: digest,
        force: force
      )
    end
  end
end
