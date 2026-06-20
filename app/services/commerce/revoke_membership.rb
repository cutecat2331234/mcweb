# frozen_string_literal: true

module Commerce
  class RevokeMembership < ApplicationService
    def initialize(membership:, revoke_game_permissions: true)
      @membership = membership
      @revoke_game_permissions = revoke_game_permissions
    end

    def call
      return ServiceResult.success(@membership) unless @membership.active?

      type = @membership.membership_type
      user = @membership.user

      @membership.update!(status: :revoked)

      if @revoke_game_permissions && type.game_permission_enabled?
        still_active = Commerce::UserMembership
          .currently_active
          .where(user: user, store_membership_type_id: type.id)
          .exists?

        unless still_active
          Commerce::DispatchMembershipCommands.call(
            user: user,
            membership_type: type,
            commands: type.resolved_revoke_commands
          )
        end
      end

      ServiceResult.success(@membership)
    end
  end
end
