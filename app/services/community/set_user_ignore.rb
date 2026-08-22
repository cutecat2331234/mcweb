# frozen_string_literal: true

module Community
  class SetUserIgnore < ApplicationService
    def initialize(ignorer:, ignored_username:, desired_state: nil)
      @ignorer = ignorer
      @ignored = User.find_by(username: ignored_username.to_s.strip)
      @desired_state = desired_state
    end

    def call
      return ServiceResult.failure(error: :user_not_found) unless @ignored
      return ServiceResult.failure(error: :cannot_ignore_self) if @ignorer.id == @ignored.id

      mutation = Community::SetUserRelationship.call(
        relation: Community::UserIgnore.where(ignorer: @ignorer, ignored: @ignored),
        desired_state: @desired_state
      )
      return mutation if mutation.failure?

      ServiceResult.success(ignored: mutation.value[:active], changed: mutation.value[:changed])
    end
  end
end
