# frozen_string_literal: true

module Commerce
  class ExpireMembershipsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Commerce::UserMembership.expired_pending.includes(:membership_type, :user).find_each do |membership|
        type = membership.membership_type
        user = membership.user

        membership.expire!

        next unless type.game_permission_enabled?

        still_active = Commerce::UserMembership
          .currently_active
          .where(user: user, store_membership_type_id: type.id)
          .exists?

        next if still_active

        Commerce::DispatchMembershipCommands.call(
          user: user,
          membership_type: type,
          commands: type.resolved_revoke_commands
        )
      end
    end
  end
end
