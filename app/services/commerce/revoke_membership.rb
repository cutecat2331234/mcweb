# frozen_string_literal: true

module Commerce
  class RevokeMembership < ApplicationService
    def initialize(membership:, revoke_game_permissions: true, idempotency_key: nil)
      @membership = membership
      @revoke_game_permissions = revoke_game_permissions
      @idempotency_key = idempotency_key
    end

    def call
      type = @membership.membership_type
      user = @membership.user
      command_result = nil
      revoked = false

      Commerce::UserMembership.transaction do
        user.lock!
        @membership.lock!
        @membership.reload

        if @membership.active?
          @membership.update!(status: :revoked)
          revoked = true
        elsif !@membership.revoked?
          next
        end

        next unless should_dispatch_commands?(user, type)

        command_result = Commerce::DispatchMembershipCommands.call(
          user: user,
          membership_type: type,
          commands: type.resolved_revoke_commands,
          idempotency_key: @idempotency_key
        )
        raise ActiveRecord::Rollback if command_result.failure?
      end

      return command_result if command_result&.failure?

      ServiceResult.success(
        membership: @membership.reload,
        revoked: revoked,
        command: command_result&.value.to_h
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def should_dispatch_commands?(user, type)
      return false unless @revoke_game_permissions && type.game_permission_enabled?

      Commerce::UserMembership
        .currently_active
        .where(user: user, store_membership_type_id: type.id)
        .where.not(id: @membership.id)
        .none?
    end
  end
end
