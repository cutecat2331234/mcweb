# frozen_string_literal: true

module Community
  module TopicListPreloadable
    extend ActiveSupport::Concern

    TOPIC_LIST_INCLUDES = [ :user, :section, :last_post_user, :tags, :linked_product, :assigned_to ].freeze

    private

    def preload_topics(scope)
      scope.includes(TOPIC_LIST_INCLUDES)
    end

    def attach_participant_users!(topics, limit: 5)
      topics = topics.to_a
      return topics if topics.empty?

      topic_ids = topics.map(&:id)
      authors_by_topic = topics.index_by(&:id).transform_values(&:user_id)
      rows = Community::Post
        .where(forum_topic_id: topic_ids, status: :published)
        .order(forum_topic_id: :asc, created_at: :desc)
        .pluck(:forum_topic_id, :user_id)

      participants_by_topic = Hash.new { |hash, key| hash[key] = [] }
      rows.each do |topic_id, user_id|
        next if user_id == authors_by_topic[topic_id]
        next if participants_by_topic[topic_id].include?(user_id)
        next if participants_by_topic[topic_id].size >= limit

        participants_by_topic[topic_id] << user_id
      end

      user_ids = participants_by_topic.values.flatten.uniq
      users_by_id = User.where(id: user_ids).index_by(&:id)

      topics.each do |topic|
        topic.participant_users_preloaded = participants_by_topic[topic.id].filter_map { |id| users_by_id[id] }
      end

      topics
    end

    def serialize_topics(topics, read_states: {}, highlight_query: nil)
      topics = attach_participant_users!(topics)
      topics.map { |topic| serialize_topic(topic, read_state: read_states[topic.id], highlight_query: highlight_query) }
    end
  end
end
