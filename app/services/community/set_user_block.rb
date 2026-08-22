# frozen_string_literal: true

module Community
  class SetUserBlock < ApplicationService
    def initialize(blocker:, blocked_username:, desired_state: nil)
      @blocker = blocker
      @blocked = User.find_by(username: blocked_username.to_s.strip)
      @desired_state = desired_state
    end

    def call
      return ServiceResult.failure(error: :user_not_found) unless @blocked
      return ServiceResult.failure(error: :you_cannot_block_yourself) if @blocker.id == @blocked.id

      mutation = Community::SetUserRelationship.call(
        relation: Community::UserBlock.where(blocker: @blocker, blocked: @blocked),
        desired_state: @desired_state
      )
      return mutation if mutation.failure?

      ServiceResult.success(blocked: mutation.value[:active], changed: mutation.value[:changed])
    end
  end
end
