module Community
  class ReadState < ApplicationRecord
    belongs_to :user
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id

    validates :user_id, uniqueness: { scope: :forum_topic_id }

    EXCLUDED_UNREAD_POST_TYPES = %w[whisper small_action].freeze

    def self.mark_read!(user, topic, floor:)
      state = find_or_initialize_by(user: user, topic: topic)
      state.last_read_floor = [ state.last_read_floor, floor ].max
      state.save!
    end

    # Ensure subscribers who receive notifications but never opened the topic still appear in unread lists.
    def self.ensure_tracking!(user, topic)
      find_or_create_by!(user: user, topic: topic) do |state|
        state.last_read_floor = 0
      end
    end

    def self.first_unread_floor(user, topic)
      state = find_by(user: user, topic: topic)
      last_read = state&.last_read_floor.to_i
      topic.posts.where(status: :published).where.not(post_type: EXCLUDED_UNREAD_POST_TYPES).where("floor_number > ?", last_read).minimum(:floor_number)
    end

    def self.page_for_floor(floor, per_page: 20)
      return 1 if floor.to_i <= 0

      ((floor.to_i - 1) / per_page) + 1
    end

    def unread_count
      topic.posts.where(status: :published).where.not(post_type: EXCLUDED_UNREAD_POST_TYPES).where("floor_number > ?", last_read_floor).count
    end

    scope :with_unread_for, ->(user) {
      joins(:topic)
        .where(user: user, forum_topics: { status: :published, unlisted: false })
        .where(<<~SQL.squish)
          EXISTS (
            SELECT 1 FROM forum_posts
            WHERE forum_posts.forum_topic_id = forum_read_states.forum_topic_id
              AND forum_posts.status = 'published'
              AND forum_posts.post_type NOT IN ('whisper', 'small_action')
              AND forum_posts.floor_number > forum_read_states.last_read_floor
          )
        SQL
        .order("forum_topics.last_posted_at DESC")
    }

    scope :unread_topics_count_for, ->(user) {
      with_unread_for(user).count
    }

    def self.unread_count_for_section(user, section)
      topic_ids = section.topics.where(status: :published).select(:id)
      with_unread_for(user).where(forum_topic_id: topic_ids).count
    end
  end
end
