# frozen_string_literal: true

module Commerce
  class SyncMembershipGamePermissions < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      return ServiceResult.success(synced: 0) unless @user

      synced = 0

      Commerce::UserMembership
        .includes(:membership_type)
        .where(user: @user)
        .find_each do |membership|
          type = membership.membership_type
          next unless type.game_permission_enabled?

          if membership.currently_active?
            next if type.game_permission_website_managed? && !needs_grant?(membership)

            Commerce::DispatchMembershipCommands.call(
              user: @user,
              membership_type: type,
              commands: type.resolved_grant_commands
            )
            synced += 1
          elsif membership.active? && membership.expires_at.present? && membership.expires_at <= Time.current
            membership.expire!
            Commerce::DispatchMembershipCommands.call(
              user: @user,
              membership_type: type,
              commands: type.resolved_revoke_commands
            )
            synced += 1
          end
        end

      ServiceResult.success(synced: synced)
    end

    private

    def needs_grant?(membership)
      # website_managed: only re-grant on presence sync when membership was just extended or newly active
      membership.source_order_item_id.present? &&
        membership.updated_at > 5.minutes.ago
    end
  end
end
