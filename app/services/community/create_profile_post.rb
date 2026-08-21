# frozen_string_literal: true

module Community
  class CreateProfilePost < ApplicationService
    def initialize(author:, profile_user:, body:)
      @author = author
      @profile_user = profile_user
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "profile_posts_disabled") unless Community::ProfileWallPolicy.enabled?
      unless Community::ProfileWallPolicy.can_post?(author: @author, profile_user: @profile_user)
        return ServiceResult.failure(error: "profile_post_not_allowed")
      end
      prepared = Community::PrepareProfileWallBody.call(author: @author, body: @body, max_length: 5_000)
      return prepared if prepared.failure?

      post = Community::ProfilePost.create!(
        profile_user: @profile_user,
        author: @author,
        body: prepared.value,
        status: :published
      )
      notify_owner!(post, prepared.value)
      ServiceResult.success(post)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def notify_owner!(post, body)
      return if @profile_user.id == @author.id
      return unless NotificationPreference.enabled?(@profile_user, channel: "in_app", notification_type: "forum.profile_post")

      Community::InAppNotification.notify(
        user: @profile_user,
        notification_type: "forum.profile_post",
        key: "profile_post",
        author: @author.username,
        excerpt: body.truncate(140),
        metadata: {
          path: "/app/forum/users/#{@profile_user.username}",
          profile_post_id: post.id,
          actor: @author.username
        }
      )
    end
  end
end
