# frozen_string_literal: true

module Community
  class NotifyPostQuoted < ApplicationService
    def initialize(post:, quoter:, quoted_post:)
      @post = post
      @quoter = quoter
      @quoted_post = quoted_post
      @topic = post.topic
    end

    def call
      author = @quoted_post.user
      return ServiceResult.success if author.id == @quoter.id
      return ServiceResult.success unless NotificationPreference.enabled?(author, channel: "in_app", notification_type: "forum.quote")

      Notification.notify!(
        user: author,
        notification_type: "forum.quote",
        title: "#{@quoter.username} 引用了你的帖子",
        body: @topic.title.truncate(80),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          quoted_post_id: @quoted_post.id,
          path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
        }
      )

      ServiceResult.success
    end
  end
end
