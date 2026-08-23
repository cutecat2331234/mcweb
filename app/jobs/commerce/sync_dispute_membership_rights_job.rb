# frozen_string_literal: true

module Commerce
  class SyncDisputeMembershipRightsJob < ApplicationJob
    queue_as :minecraft

    def perform(membership_id, action, idempotency_key)
      Commerce::UserMembership.transaction do
        membership = Commerce::UserMembership.find_by(id: membership_id)
        next unless membership

        user = User.lock.find(membership.user_id)
        membership_type = Commerce::MembershipType.lock.find(
          membership.store_membership_type_id
        )
        next unless membership_type.game_permission_enabled?

        memberships = Commerce::UserMembership
          .where(user_id: user.id, store_membership_type_id: membership_type.id)
          .order(:id)
          .lock
          .to_a
        membership = memberships.find { |item| item.id == membership.id }
        next unless membership

        commands = aggregate_commands(
          memberships:,
          membership_type:,
          action: action.to_s
        )
        next unless commands

        result = Commerce::DispatchMembershipCommands.call(
          user:,
          membership_type:,
          commands:,
          idempotency_key: aggregate_idempotency_key(
            idempotency_key,
            user:,
            membership_type:,
            action: action.to_s
          )
        )
        raise result.error.to_s if result.failure?
      end
    end

    private

    def aggregate_commands(memberships:, membership_type:, action:)
      case action
      when "grant"
        return unless memberships.any?(&:currently_active?)

        membership_type.resolved_grant_commands
      when "revoke"
        return if memberships.any?(&:currently_active?)

        membership_type.resolved_revoke_commands
      end
    end

    def aggregate_idempotency_key(idempotency_key, user:, membership_type:, action:)
      scope = idempotency_key.to_s.sub(
        /:(?:freeze|revoke|restore):Commerce::UserMembership:\d+\z/,
        ""
      )
      digest = Digest::SHA256.hexdigest(
        [ scope, user.id, membership_type.id, action ].join(":")
      ).first(32)
      "dispute-rights:#{digest}"
    end
  end
end
