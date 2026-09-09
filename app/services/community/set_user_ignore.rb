# frozen_string_literal: true

module Community
  class SetUserIgnore < ApplicationService
    def initialize(ignorer:, ignored_username:, desired_state: nil, expected_revision: nil)
      @ignorer = ignorer
      @ignored = User.find_by(username: ignored_username.to_s.strip)
      @desired_state = desired_state
      @expected_revision = expected_revision
    end

    def call
      return ServiceResult.failure(error: :user_not_found) unless @ignored
      return ServiceResult.failure(error: :cannot_ignore_self) if @ignorer.id == @ignored.id

      mutation = Community::SetUserRelationship.call(
        relation: Community::UserIgnore.where(ignorer: @ignorer, ignored: @ignored),
        desired_state: @desired_state,
        expected_revision: @expected_revision,
        participants: [ @ignorer, @ignored ]
      )
      return mutation if mutation.failure?

      ServiceResult.success(mutation.value.merge(ignored: mutation.value[:active]))
    end
  end
end
