# frozen_string_literal: true

module Minecraft
  class PrimaryAccountChangeEvent < ApplicationRecord
    self.table_name = "minecraft_primary_account_change_events"

    belongs_to :user
    belongs_to :from_identity_link, class_name: "Minecraft::IdentityLink", optional: true
    belongs_to :to_identity_link, class_name: "Minecraft::IdentityLink"
    belongs_to :actor, class_name: "User"
    belongs_to :primary_account_change_request,
               class_name: "Minecraft::PrimaryAccountChangeRequest",
               optional: true

    validates :change_source,
              inclusion: {
                in: %w[player_immediate staff_approval administrator_override automatic_successor]
              }
    validates :idempotency_key_digest,
              presence: true,
              length: { is: 64 },
              format: { with: /\A[0-9a-f]{64}\z/ },
              uniqueness: { scope: :user_id }
    validates :changed_at, presence: true
    validates :reason, length: { maximum: 2_000 }, allow_nil: true
    validate :links_belong_to_user
    validate :distinct_links
    validate :administrator_reason_present

    scope :for_cooldown, -> { where(counts_for_cooldown: true) }
    scope :recent_first, -> { order(changed_at: :desc, id: :desc) }

    before_update { throw(:abort) }
    before_destroy { throw(:abort) }

    private

    def links_belong_to_user
      errors.add(:to_identity_link, :invalid) if to_identity_link&.user_id != user_id
      return if from_identity_link.nil? || from_identity_link.user_id == user_id

      errors.add(:from_identity_link, :invalid)
    end

    def distinct_links
      return unless to_identity_link_id.present? && to_identity_link_id == from_identity_link_id

      errors.add(:to_identity_link, :invalid)
    end

    def administrator_reason_present
      return unless change_source == "administrator_override" && reason.blank?

      errors.add(:reason, :blank)
    end
  end
end
