# frozen_string_literal: true

module Community
  class SendForumDigest < ApplicationService
    FREQUENCIES = %w[daily weekly].freeze
    NOTIFICATION_TYPES = %w[
      forum.topic_reply forum.mention forum.section_topic forum.private_message
      forum.followed_topic forum.followed_reply forum.tag_topic forum.reaction
    ].freeze

    def initialize(user:)
      @user = user
    end

    def call
      frequency = @user.forum_digest_frequency
      return ServiceResult.success(skipped: true) unless FREQUENCIES.include?(frequency)
      return ServiceResult.success(skipped: true) unless due_for_digest?(frequency)

      since = @user.forum_digest_last_sent_at || digest_window(frequency).ago
      notifications = @user.notifications
        .where("created_at > ?", since)
        .where(notification_type: NOTIFICATION_TYPES)
        .order(created_at: :desc)
        .limit(50)

      notifications = filter_watched_notifications(notifications.to_a) if @user.forum_digest_watched_only?

      return ServiceResult.success(skipped: true) if notifications.none?

      MailDeliveryJob.perform_later(
        "Community::ForumMailer",
        "digest",
        "deliver_now",
        args: [ @user.id, notifications.map(&:id) ]
      )
      Notification.where(id: notifications.map(&:id)).update_all(read_at: Time.current)
      @user.update!(forum_digest_last_sent_at: Time.current)
      ServiceResult.success(sent: true, count: notifications.count)
    end

    private

    def due_for_digest?(frequency)
      last = @user.forum_digest_last_sent_at
      return true if last.nil?

      case frequency
      when "daily" then last < 1.day.ago
      when "weekly" then last < 1.week.ago
      else false
      end
    end

    def digest_window(frequency)
      frequency == "weekly" ? 1.week : 1.day
    end

    def filter_watched_notifications(notifications)
      watched_topic_ids = Community::Subscription.where(user: @user, subscribable_type: "Community::Topic")
        .pluck(:subscribable_id)
      watched_section_ids = Community::Subscription.where(user: @user, subscribable_type: "Community::Section")
        .pluck(:subscribable_id)
      watched_tag_ids = Community::Subscription.where(user: @user, subscribable_type: "Community::Tag")
        .pluck(:subscribable_id)

      return [] if watched_topic_ids.empty? && watched_section_ids.empty? && watched_tag_ids.empty?

      notifications.select do |notification|
        metadata = notification.metadata || {}
        topic_public_id = metadata["topic_id"] || metadata[:topic_id]
        next false if topic_public_id.blank?

        topic = Community::Topic.find_by(public_id: topic_public_id)
        next false unless topic

        watched_topic_ids.include?(topic.id) ||
          watched_section_ids.include?(topic.forum_section_id) ||
          topic.tags.where(id: watched_tag_ids).exists?
      end
    end
  end
end
