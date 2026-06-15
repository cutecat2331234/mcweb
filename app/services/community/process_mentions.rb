# frozen_string_literal: true

module Community
  class ProcessMentions < ApplicationService
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    GROUP_MENTIONS = {
      "staff" => -> { staff_users },
      "moderators" => -> { staff_users }
    }.freeze

    def initialize(body:, author:, post:, topic:)
      @body = body.to_s
      @author = author
      @post = post
      @topic = topic
    end

    def call
      tokens = @body.scan(MENTION_PATTERN).flatten.uniq
      return ServiceResult.success(mentioned: []) if tokens.empty?

      mentioned_users = []
      tokens.each do |token|
        if GROUP_MENTIONS.key?(token.downcase)
          mentioned_users.concat(GROUP_MENTIONS[token.downcase].call.to_a)
        else
          user = User.find_by(username: token)
          mentioned_users << user if user && user.id != @author.id
        end
      end

      mentioned_users.uniq.each do |user|
        notify_user!(user)
      end

      ServiceResult.success(mentioned: mentioned_users.map(&:username).uniq)
    end

    private

    def self.staff_users
      User.joins(roles: :permissions)
        .where(permissions: { key: "forum.topics.lock" })
        .distinct
    end

    def staff_users
      self.class.staff_users
    end

    def notify_user!(user)
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.mention")

      Notification.notify!(
        user: user,
        notification_type: "forum.mention",
        title: "#{@author.username} 在主题中提到了你",
        body: @body.truncate(120),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          path: Community::PostPermalink.path(@topic, @post)
        }
      )

      if NotificationPreference.enabled?(user, channel: "email", notification_type: "forum.mention")
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "mention",
          "deliver_now",
          args: [ user.id, @topic.public_id, @post.id ]
        )
      end
    end
  end
end
