# frozen_string_literal: true

module Community
  class SendForumDigest < ApplicationService
    FREQUENCIES = %w[daily weekly].freeze

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
        .where(notification_type: %w[forum.topic_reply forum.mention forum.section_topic forum.private_message forum.followed_topic])
        .order(created_at: :desc)
        .limit(50)

      return ServiceResult.success(skipped: true) if notifications.none?

      MailDeliveryJob.perform_later(
        "Community::ForumMailer",
        "digest",
        "deliver_now",
        args: [ @user.id, notifications.pluck(:id) ]
      )
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
  end
end
