# frozen_string_literal: true

module Minecraft
  class SkinRefreshRequest < ApplicationRecord
    STALE_RUNNING_AFTER = 15.minutes

    belongs_to :player_identity, class_name: "Minecraft::PlayerIdentity"
    belongs_to :requested_by, class_name: "User", optional: true

    enum :status,
         {
           pending: "pending",
           running: "running",
           succeeded: "succeeded",
           failed: "failed"
         },
         validate: true

    validates :idempotency_key_digest,
              presence: true,
              length: { is: 64 },
              uniqueness: { scope: :player_identity_id }
    validates :trigger, presence: true, length: { maximum: 40 }
    validates :error_code, length: { maximum: 100 }, allow_nil: true

    def terminal?
      succeeded? || failed?
    end

    def stale_running?(at: Time.current)
      running? && started_at.present? && started_at <= at - STALE_RUNNING_AFTER
    end
  end
end
