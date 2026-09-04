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
      return ServiceResult.failure(error: "profile_post_unavailable") unless @profile_post&.published?
      unless Community::ProfileWallPolicy.can_comment?(author: @author, profile_post: @profile_post)
        return ServiceResult.failure(error: "profile_post_not_allowed")
      end
      prepared = Community::PrepareProfileWallBody.call(author: @author, body: @body, max_length: 3_000)
      return prepared if prepared.failure?

      comment = nil
      state_result = nil
      Community::ProfilePostComment.transaction do
        @author = User.lock.find(@author.id)
        state_result = account_write_access_result
        raise ActiveRecord::Rollback if state_result.failure?

        @profile_post = Community::ProfilePost.lock.find_by(id: @profile_post.id)
        unless @profile_post&.published? &&
            Community::ProfileWallPolicy.can_comment?(
              author: @author,
              profile_post: @profile_post
            )
          state_result = ServiceResult.failure(error: "profile_post_not_allowed")
          raise ActiveRecord::Rollback
        end

        comment = @profile_post.comments.create!(
          author: @author,
          body: prepared.value,
          status: :published
        )
      end
      return state_result if state_result&.failure?

      notify_recipients!(comment, prepared.value)
      ServiceResult.success(comment)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def account_write_access_result
      return ServiceResult.failure(error: :account_deleted) if @author.deleted?
      return ServiceResult.failure(error: :account_banned) if @author.banned?

      ServiceResult.success
    end

    def notify_recipients!(comment, body)
      [ @profile_post.author, @profile_post.profile_user ].compact.uniq.each do |user|
        next if user.id == @author.id
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.profile_post_comment")

        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.profile_post_comment",
          key: "profile_post_comment",
          author: @author.username,
          excerpt: body.truncate(140),
          metadata: {
            path: "/app/forum/users/#{@profile_post.profile_user.username}",
            profile_post_id: @profile_post.id,
            profile_post_comment_id: comment.id,
            actor: @author.username
          }
        )
      end
    end
  end
end
