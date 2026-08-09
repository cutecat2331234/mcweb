# frozen_string_literal: true

require "digest"

module Minecraft
  class IdentityLink < ApplicationRecord
    belongs_to :player_profile, class_name: "Minecraft::PlayerProfile"
    belongs_to :user
    has_many :primary_account_change_requests_as_target,
             class_name: "Minecraft::PrimaryAccountChangeRequest",
             foreign_key: :target_identity_link_id,
             dependent: :restrict_with_error
    has_many :primary_account_change_requests_as_source,
             class_name: "Minecraft::PrimaryAccountChangeRequest",
             foreign_key: :source_identity_link_id,
             dependent: :restrict_with_error
    has_many :primary_account_change_events_as_from,
             class_name: "Minecraft::PrimaryAccountChangeEvent",
             foreign_key: :from_identity_link_id,
             dependent: :restrict_with_error
    has_many :primary_account_change_events_as_to,
             class_name: "Minecraft::PrimaryAccountChangeEvent",
             foreign_key: :to_identity_link_id,
             dependent: :restrict_with_error

    validates :linked_at, presence: true
    validates :primary_account,
              uniqueness: {
                scope: :user_id,
                conditions: -> { where(unlinked_at: nil, primary_account: true) }
              },
              if: :primary_account?
    validate :primary_account_must_be_active

    scope :active, -> { where(unlinked_at: nil) }
    scope :primary, -> { active.where(primary_account: true) }

    before_validation :select_primary_if_first_link, on: :create

    def unlink!
      user.with_lock do
        was_primary = primary_account?
        unlinked_at = Time.current
        update!(unlinked_at: unlinked_at, primary_account: false)

        if was_primary
          successor = self.class.active
                                .where(user_id: user_id)
                                .order(:linked_at, :id)
                                .first
          if successor
            successor.update!(primary_account: true)
            digest = Digest::SHA256.hexdigest(
              "minecraft-primary-successor:#{id}:#{successor.id}:#{unlinked_at.iso8601(6)}"
            )
            event = Minecraft::PrimaryAccountChangeEvent.create!(
              user: user,
              from_identity_link: self,
              to_identity_link: successor,
              actor: user,
              change_source: "automatic_successor",
              idempotency_key_digest: digest,
              reason: "primary_account_unlinked",
              counts_for_cooldown: false,
              changed_at: unlinked_at
            )
            Administration::AuditLogger.call(
              actor: user,
              action: "minecraft.primary_account_changed",
              resource: successor.player_profile,
              request_id: "minecraft-primary-successor-#{event.id}",
              reason: "primary_account_unlinked",
              before_state: { player_id: player_profile.public_id },
              after_state: { player_id: successor.player_profile.public_id },
              metadata: {
                user_id: user_id,
                from_identity_link_id: id,
                to_identity_link_id: successor.id,
                change_source: "automatic_successor"
              }
            )
          end
        end

        Minecraft::CancelPrimaryAccountRequestsForLink.call(
          identity_link: self,
          actor: user,
          reason: "identity_link_unlinked"
        )
      end

      self
    end

    private

    def primary_account_must_be_active
      return unless primary_account? && unlinked_at.present?

      errors.add(:primary_account, :invalid)
    end

    def select_primary_if_first_link
      return if unlinked_at.present? || primary_account?
      return if self.class.active.where(user_id: user_id).exists?

      self.primary_account = true
    end
  end
end
