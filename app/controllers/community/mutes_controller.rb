# frozen_string_literal: true

module Community
  class MutesController < ApplicationController
    before_action :require_login

    def index
      topic_mutes = Community::TopicMute
        .where(user: current_user)
        .includes(topic: :section)
        .order(created_at: :desc)

      section_mutes = Community::SectionMute
        .where(user: current_user)
        .includes(:section)
        .order(created_at: :desc)

      render inertia: "Community/Muted/Index", props: {
        topicMutes: topic_mutes.map do |mute|
          topic = mute.topic
          {
            id: mute.id,
            title: topic.title,
            topic_url: forum_topic_path(topic),
            section_name: topic.section.name,
            muted_at: l(mute.created_at, format: :short),
            unmute_url: mute_forum_topic_path(topic)
          }
        end,
        sectionMutes: section_mutes.map do |mute|
          section = mute.section
          {
            id: mute.id,
            name: section.name,
            section_url: forum_section_path(section),
            muted_at: l(mute.created_at, format: :short),
            unmute_url: mute_forum_section_path(section)
          }
        end
      }
    end
  end
end
