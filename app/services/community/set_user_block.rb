# frozen_string_literal: true

module Community
  class SetUserBlock < ApplicationService
    def initialize(blocker:, blocked_username:, desired_state: nil, expected_revision: nil)
      @blocker = blocker
      @blocked = User.find_by(username: blocked_username.to_s.strip)
      @desired_state = desired_state
      @expected_revision = expected_revision
    end

    def call
      return ServiceResult.failure(error: :user_not_found) unless @blocked
      return ServiceResult.failure(error: :you_cannot_block_yourself) if @blocker.id == @blocked.id

      mutation = Community::SetUserRelationship.call(
        relation: Community::UserBlock.where(blocker: @blocker, blocked: @blocked),
        desired_state: @desired_state,
        expected_revision: @expected_revision,
        participants: [ @blocker, @blocked ]
      )
      return mutation if mutation.failure?

      if mutation.value[:active]
        Community::RevokeBlockedConversationInvitations.call(
          first_user: @blocker,
          second_user: @blocked
        )
      end

      ServiceResult.success(mutation.value.merge(blocked: mutation.value[:active]))
    end
  end
end
