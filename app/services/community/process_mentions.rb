# frozen_string_literal: true

module Community
  class ProcessMentions < ApplicationService
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    GROUP_MENTION_METHODS = {
      "staff" => :staff_users,
      "moderators" => :staff_users,
      "here" => :topic_participants
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
      group_tokens = []
      tokens.each do |token|
        method = GROUP_MENTION_METHODS[token.downcase]
        if method
          group_tokens << token.downcase
          mentioned_users.concat(send(method).to_a)
        else
          user = User.find_by(username: token)
          mentioned_users << user if user && user.id != @author.id
        end
      end

      mentioned_users.uniq.each do |user|
        next unless mention_visible_to?(user)
        notify_user!(user, group_mention: group_tokens.include?("here"))
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

    def topic_participants
      user_ids = @topic.posts.where(status: :published).distinct.pluck(:user_id)
      user_ids << @topic.user_id
      User.where(id: user_ids.uniq).where.not(id: @author.id)
    end

    def notify_user!(user, group_mention: false)
      notification_type = group_mention ? "forum.here" : "forum.mention"
      return unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: notification_type)

      title_key = group_mention ? "here" : "mention"
      Community::InAppNotification.notify(
        user: user,
        notification_type: notification_type,
        key: title_key,
        author: @author.username,
        excerpt: @body.truncate(120),
        metadata: {
          topic_id: @topic.public_id,
          post_id: @post.id,
          path: Community::PostPermalink.path(@topic, @post)
        }
      )

      if Community::InstantEmailDelivery.allowed?(user, notification_type: notification_type)
        mailer_action = group_mention ? "here" : "mention"
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          mailer_action,
          "deliver_now",
          args: [ user.id, @topic.public_id, @post.id ]
        )
      end
    end

    def mention_visible_to?(user)
      return false unless PollParticipation.visible?(topic: @topic, user: user)
      return true unless @topic.unlisted?

      user.id == @topic.user_id || user.permission?("forum.topics.lock")
    end
  end
end
