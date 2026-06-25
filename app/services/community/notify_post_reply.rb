# frozen_string_literal: true

module Community
  # XenForo-style "someone replied to your post": notifies the parent post's
  # author when a reply targets their post. In-app only. Skips self-replies and
  # cases already covered by the quote notification.
  class NotifyPostReply < ApplicationService
    def initialize(post:, replier:, parent_post:)
      @post = post
      @replier = replier
      @parent_post = parent_post
      @topic = post.topic
    end

    def call
      author = @parent_post.user
      return ServiceResult.success if author.nil? || author.id == @replier.id
      # A reply that also quotes the same post already triggers the quote notification.
      return ServiceResult.success if @post.quoted_post_id == @parent_post.id

      allowed = Community::FilterNotificationRecipients.call(
        actor_id: @replier.id,
        recipient_ids: [ author.id ],
        topic: @topic
      ).value
      return ServiceResult.success unless allowed.include?(author.id)
      return ServiceResult.success unless NotificationPreference.enabled?(author, channel: "in_app", notification_type: "forum.post_reply")

      Community::InAppNotification.notify(
        user: author,
        notification_type: "forum.post_reply",
        key: "post_reply",
        actor: @replier.username,
        excerpt: @topic.title.truncate(80),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          parent_post_id: @parent_post.id,
          path: Community::PostPermalink.path(@topic, @post)
        }
      )

      ServiceResult.success
    end
  end
end
