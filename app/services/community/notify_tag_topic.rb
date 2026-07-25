# frozen_string_literal: true

module Community
  class NotifyTagTopic < ApplicationService
    def initialize(topic:, tags:)
      @topic = topic
      @tags = Array(tags)
    end

    def call
      return ServiceResult.success if @tags.empty?
      return ServiceResult.success if @topic.unlisted? || @topic.status != "published"

      tag_ids = @tags.filter_map(&:id).uniq
      subscription_rows = Community::Subscription
        .where(subscribable_type: "Community::Tag", subscribable_id: tag_ids)
        .where.not(user_id: @topic.user_id)
        .pluck(:user_id, :subscribable_id, :notification_level)
      subscriptions_by_user = subscription_rows.group_by(&:first)

      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @topic.user_id,
        recipient_ids: subscriptions_by_user.keys,
        topic: @topic
      ).value

      User.where(id: recipient_ids).find_each do |user|
        eligible_tags = Community::NotificationAccess.tag_topic_tags(
          user: user,
          topic: @topic,
          tag_ids: subscriptions_by_user.fetch(user.id, []).map(&:second)
        )
        next if eligible_tags.empty?

        eligible_tag_ids = eligible_tags.map(&:id)
        levels = subscriptions_by_user.fetch(user.id, []).filter_map do |_, tag_id, level|
          level if eligible_tag_ids.include?(tag_id)
        end
        level = effective_notification_level(levels)
        next unless NotificationLevelFilter.deliver_in_app?(level: level, user: user, context: :tag_topic)
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.tag_topic")

        Community::ReadState.ensure_tracking!(user, @topic)

        tag_names = eligible_tags.map(&:name).join(", ")
        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.tag_topic",
          key: "tag_topic",
          title: @topic.title.truncate(60),
          author: @topic.user.username,
          tags: tag_names,
          metadata: {
            topic_id: @topic.public_id,
            tag_ids: eligible_tag_ids,
            path: "/app/forum/topics/#{@topic.public_id}"
          }
        )

        if NotificationLevelFilter.deliver_watch_email?(
          level: level,
          user: user,
          notification_type: "forum.tag_topic"
        ) && Community::WatchEmailDelivery.email_allowed?(user, notification_type: "forum.tag_topic")
          MailDeliveryJob.perform_later(
            "Community::ForumMailer",
            "tag_topic",
            "deliver_now",
            args: [ user.id, @topic.public_id, eligible_tag_ids ]
          )
        end
      end

      ServiceResult.success
    end

    private

    def effective_notification_level(levels)
      %w[watching tracking normal].find { |level| levels.include?(level) } || "normal"
    end
  end
end
