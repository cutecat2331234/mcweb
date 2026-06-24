# frozen_string_literal: true

module Community
  class CreateProfilePostComment < ApplicationService
    def initialize(author:, profile_post:, body:)
      @author = author
      @profile_post = profile_post
      @body = body.to_s.strip
    end

    def call
      return ServiceResult.failure(error: "profile_posts_disabled") unless Community::ProfileWallPolicy.enabled?
      return ServiceResult.failure(error: "profile_post_blank") if @body.blank?
      return ServiceResult.failure(error: "profile_post_unavailable") unless @profile_post&.published?
      unless Community::ProfileWallPolicy.can_comment?(author: @author, profile_post: @profile_post)
        return ServiceResult.failure(error: "profile_post_not_allowed")
      end

      comment = @profile_post.comments.create!(author: @author, body: @body, status: :published)
      notify_recipients!(comment)
      ServiceResult.success(comment)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def notify_recipients!(_comment)
      [ @profile_post.author, @profile_post.profile_user ].compact.uniq.each do |user|
        next if user.id == @author.id
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.profile_post_comment")

        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.profile_post_comment",
          key: "profile_post_comment",
          author: @author.username,
          excerpt: @body.truncate(140),
          metadata: {
            path: "/app/forum/users/#{@profile_post.profile_user.username}",
            profile_post_id: @profile_post.id,
            actor: @author.username
          }
        )
      end
    end
  end
end
