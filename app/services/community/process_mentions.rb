# frozen_string_literal: true

module Community
  class ProcessMentions < ApplicationService
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    def initialize(body:, author:, post:, topic:)
      @body = body.to_s
      @author = author
      @post = post
      @topic = topic
    end

    def call
      usernames = @body.scan(MENTION_PATTERN).flatten.uniq
      return ServiceResult.success(mentioned: []) if usernames.empty?

      users = User.where(username: usernames).where.not(id: @author.id)
      users.find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.mention")

        Notification.notify!(
          user: user,
          notification_type: "forum.mention",
          title: "#{@author.username} 在主题中提到了你",
          body: @body.truncate(120),
          metadata: {
            topic_id: @topic.public_id,
            post_id: @post.id,
            path: "/forum/topics/#{@topic.public_id}#post-#{@post.id}"
          }
        )
      end

      ServiceResult.success(mentioned: users.pluck(:username))
    end
  end
end
