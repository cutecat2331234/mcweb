# frozen_string_literal: true

module Community
  class PreferencesController < ApplicationController
    before_action :require_login

    NOTIFICATION_TYPES = %w[
      forum.topic_reply
      forum.mention
      forum.section_topic
      forum.private_message
    ].freeze

    CHANNELS = %w[in_app email].freeze

    def show
      prefs = NOTIFICATION_TYPES.map do |type|
        {
          notification_type: type,
          label: notification_label(type),
          in_app: NotificationPreference.enabled?(current_user, channel: "in_app", notification_type: type),
          email: NotificationPreference.enabled?(current_user, channel: "email", notification_type: type)
        }
      end

      render inertia: "Community/Preferences/Show", props: { preferences: prefs }
    end

    def update
      NOTIFICATION_TYPES.each do |type|
        CHANNELS.each do |channel|
          enabled = ActiveModel::Type::Boolean.new.cast(params.dig(:preferences, type, channel))
          NotificationPreference.set!(
            current_user,
            channel: channel,
            notification_type: type,
            enabled: enabled
          )
        end
      end

      redirect_to forum_preferences_path, notice: "通知偏好已保存。"
    end

    private

    def notification_label(type)
      {
        "forum.topic_reply" => "主题回复",
        "forum.mention" => "@提及",
        "forum.section_topic" => "关注分区新主题",
        "forum.private_message" => "私信"
      }[type] || type.humanize
    end
  end
end
