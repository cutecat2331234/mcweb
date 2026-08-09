# frozen_string_literal: true

module Minecraft
  class PrimaryAccountChangeRequest < ApplicationRecord
    self.table_name = "minecraft_primary_account_change_requests"

    belongs_to :user
    belongs_to :target_identity_link, class_name: "Minecraft::IdentityLink"
    belongs_to :source_identity_link, class_name: "Minecraft::IdentityLink", optional: true
    belongs_to :requested_by, class_name: "User"
    belongs_to :decided_by, class_name: "User", optional: true
    has_one :change_event,
            class_name: "Minecraft::PrimaryAccountChangeEvent",
            foreign_key: :primary_account_change_request_id,
            dependent: :restrict_with_error

    enum :status,
         {
           pending: "pending",
           approved: "approved",
           rejected: "rejected",
           expired: "expired",
           cancelled: "cancelled"
         },
         validate: true

    validates :policy_snapshot, inclusion: { in: %w[staff_approval] }
    validates :idempotency_key_digest,
              presence: true,
              length: { is: 64 },
              format: { with: /\A[0-9a-f]{64}\z/ },
              uniqueness: { scope: :user_id }
    validates :request_reason, presence: true, length: { maximum: 2_000 }
    validates :decision_reason, length: { maximum: 2_000 }, allow_nil: true
    validates :requested_at, :expires_at, presence: true
    validate :links_belong_to_user
    validate :target_link_is_active, if: :pending?
    validate :target_differs_from_source

    scope :recent_first, -> { order(requested_at: :desc, id: :desc) }
    scope :past_deadline, ->(at = Time.current) { pending.where(expires_at: ..at) }

    before_update :prevent_terminal_mutation
    before_destroy { throw(:abort) }

    def past_deadline?(at: Time.current)
      pending? && expires_at <= at
    end

    private

    def prevent_terminal_mutation
      throw(:abort) if status_was != "pending"
    end

    def links_belong_to_user
      errors.add(:target_identity_link, :invalid) if target_identity_link&.user_id != user_id
      return if source_identity_link.nil? || source_identity_link.user_id == user_id

      errors.add(:source_identity_link, :invalid)
    end

    def target_link_is_active
      return if target_identity_link&.unlinked_at.nil?

      errors.add(:target_identity_link, :invalid)
    end

    def target_differs_from_source
      return unless target_identity_link_id.present? && target_identity_link_id == source_identity_link_id

      errors.add(:target_identity_link, :invalid)
    end
  end
end
