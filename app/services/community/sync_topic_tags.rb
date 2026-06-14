# frozen_string_literal: true

module Community
  class SyncTopicTags < ApplicationService
    MAX_TAGS = 5

    def initialize(topic:, tag_names:)
      @topic = topic
      @tag_names = Array(tag_names).flat_map { |n| n.to_s.split(",") }.map(&:strip).reject(&:blank?).first(MAX_TAGS)
    end

    def call
      tags = @tag_names.filter_map { |name| Community::Tag.find_or_create_by_name!(name) }
      @topic.topic_tags.where.not(forum_tag_id: tags.map(&:id)).destroy_all
      tags.each do |tag|
        Community::TopicTag.find_or_create_by!(topic: @topic, tag: tag)
      end
      ServiceResult.success(tags: tags)
    end
  end
end
