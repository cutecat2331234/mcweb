# frozen_string_literal: true

module Community
  class TopicParticipant
    MENTION_PATTERN = /@([a-zA-Z0-9_]{3,32})/

    def self.participated?(user:, topic:)
      return true if topic.user_id == user.id

      topic.posts.where(status: :published, user_id: user.id).exists?
    end

    def self.mentioned_in_post?(user:, post:)
      post.body.to_s.scan(MENTION_PATTERN).flatten.any? { |token| token == user.username }
    end
  end
end
