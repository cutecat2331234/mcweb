# frozen_string_literal: true

module Community
  class NotifyPollClosed < ApplicationService
    def initialize(poll:, actor:)
      @poll = poll
      @topic = poll.topic
      @actor = actor
    end

    def call
      recipient_ids = collect_recipient_ids
      recipient_ids = Community::FilterNotificationRecipients.call(
        actor_id: @actor.id,
        recipient_ids: recipient_ids
      ).value

      recipient_ids.each do |user_id|
        user = User.find_by(id: user_id)
        next unless user

        notify_user(user)
      end

      ServiceResult.success
    end

    private

    def collect_recipient_ids
      ids = [ @topic.user_id ]
      ids.concat(@poll.votes.distinct.pluck(:user_id))
      watcher_ids = Community::Subscription
        .where(subscribable_type: "Community::Topic", subscribable_id: @topic.id)
        .pluck(:user_id)
      ids.concat(watcher_ids)
      ids.uniq - [ @actor.id ]
    end

    def notify_user(user)
      email_enabled = Community::InstantEmailDelivery.allowed?(user, notification_type: "forum.poll_closed")
      in_app_enabled = NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.poll_closed")
      return unless email_enabled || in_app_enabled

      if in_app_enabled
        Community::InAppNotification.notify(
          user: user,
          notification_type: "forum.poll_closed",
          key: "poll_closed",
          title: @topic.title,
          question: @poll.question,
          metadata: {
            topic_id: @topic.public_id,
            path: "#{Mcweb::Paths::APP_PREFIX}/forum/topics/#{@topic.public_id}"
          }
        )
      end

      if email_enabled
        MailDeliveryJob.perform_later(
          "Community::ForumMailer",
          "poll_closed",
          "deliver_now",
          args: [ user.id, @poll.id, @actor.id ]
        )
      end
    end
  end
end
