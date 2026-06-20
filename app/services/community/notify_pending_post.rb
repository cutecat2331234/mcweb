# frozen_string_literal: true

module Community
  class NotifyPendingPost < ApplicationService
    def initialize(post:)
      @post = post
      @topic = post.topic
    end

    def call
      section = @post.topic.section
      Community::SectionModeration.staff_users_for_section(section).find_each do |user|
        next unless NotificationPreference.enabled?(user, channel: "in_app", notification_type: "forum.post_pending")

        Notification.create!(
          user: user,
          notification_type: "forum.post_pending",
          title: I18n.t("mcweb.labels.notification_types.forum.post_pending"),
          body: I18n.t(
            "mcweb.labels.notification_bodies.forum.post_pending",
            username: @post.user.username,
            title: @topic.title.truncate(60)
          ),
          metadata: {
            path: Rails.application.routes.url_helpers.forum_topic_path(@topic, anchor: "post-#{@post.id}"),
            topic_id: @topic.public_id,
            post_id: @post.id
          }
        )
      end

      ServiceResult.success
    end
  end
end
