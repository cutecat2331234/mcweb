# frozen_string_literal: true

module Community
  class SetUserFollow < ApplicationService
    def initialize(follower:, followed_username:, desired_state: nil)
      @follower = follower
      @followed = User.find_by(username: followed_username.to_s.strip)
      @desired_state = desired_state
    end

    def call
      return ServiceResult.failure(error: :user_not_found) unless @followed
      return ServiceResult.failure(error: :cannot_follow_yourself) if @follower.id == @followed.id

      Community::UserFollow.transaction do
        mutation = Community::SetUserRelationship.call(
          relation: Community::UserFollow.where(follower: @follower, followed: @followed),
          desired_state: @desired_state,
          participants: [ @follower, @followed ]
        )
        if mutation.failure?
          mutation
        else
          notify_followed! if mutation.value[:changed] && mutation.value[:active]
          ServiceResult.success(following: mutation.value[:active], changed: mutation.value[:changed])
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      ServiceResult.failure(errors: error.record.errors.to_hash)
    end

    private

    def notify_followed!
      return unless NotificationPreference.enabled?(@followed, channel: "in_app", notification_type: "forum.new_follower")

      Community::InAppNotification.notify(
        user: @followed,
        notification_type: "forum.new_follower",
        key: "new_follower",
        author: @follower.username,
        metadata: { path: "/app/forum/users/#{@follower.username}", actor: @follower.username }
      )
    end
  end
end
