# frozen_string_literal: true

module Commerce
  class SyncDisputeMembershipRightsJob < ApplicationJob
    queue_as :minecraft

    def perform(membership_id, action, idempotency_key)
      membership = Commerce::UserMembership.includes(:membership_type, :user).find_by(id: membership_id)
      return unless membership

      membership_type = membership.membership_type
      return unless membership_type.game_permission_enabled?

      commands =
        if action.to_s == "grant" && membership.currently_active?
          membership_type.resolved_grant_commands
        elsif action.to_s == "revoke" && !membership.currently_active?
          membership_type.resolved_revoke_commands
        else
          return
        end

      result = Commerce::DispatchMembershipCommands.call(
        user: membership.user,
        membership_type: membership_type,
        commands: commands,
        idempotency_key: "dispute-rights:#{Digest::SHA256.hexdigest(idempotency_key.to_s).first(32)}"
      )
      raise result.error.to_s if result.failure?
    end
  end
end
