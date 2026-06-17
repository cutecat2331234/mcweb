# frozen_string_literal: true

module Community
  class NotifyPostReaction < ApplicationService
    def initialize(post:, reactor:, emoji:)
      @post = post
      @reactor = reactor
      @emoji = emoji
      @topic = post.topic
    end

    def call
      author = @post.user
      return ServiceResult.success if author.id == @reactor.id
      return ServiceResult.success unless Community::FilterNotificationRecipients.call(
        actor_id: @reactor.id,
        recipient_ids: [ author.id ],
        topic: @topic
      ).value.include?(author.id)

      email_enabled = Community::InstantEmailDelivery.allowed?(author, notification_type: "forum.reaction")
      in_app_enabled = NotificationPreference.enabled?(author, channel: "in_app", notification_type: "forum.reaction")
      return ServiceResult.success unless email_enabled || in_app_enabled

      if in_app_enabled
        Notification.notify!(
          user: author,
          notification_type: "forum.reaction",
          title: "#{@reactor.username} 对你的帖子做出了反应 #{@emoji}",
          body: @topic.title.truncate(80),
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
          }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "post_reaction",
          "deliver_now",
          args: [ author.id, @post.id, @reactor.id, @emoji ]
        )
      end

      ServiceResult.success
    end
  end
end
