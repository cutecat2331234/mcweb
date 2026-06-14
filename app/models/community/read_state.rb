module Community
  class ReadState < ApplicationRecord
    belongs_to :user
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id

    validates :user_id, uniqueness: { scope: :forum_topic_id }

    def self.mark_read!(user, topic, floor:)
      state = find_or_initialize_by(user: user, topic: topic)
      state.last_read_floor = [ state.last_read_floor, floor ].max
      state.save!
    end

    def self.first_unread_floor(user, topic)
      state = find_by(user: user, topic: topic)
      last_read = state&.last_read_floor.to_i
      topic.posts.where(status: :published).where("floor_number > ?", last_read).minimum(:floor_number)
    end

    def self.page_for_floor(floor, per_page: 20)
      return 1 if floor.to_i <= 0

      ((floor.to_i - 1) / per_page) + 1
    end

    def unread_count
      topic.posts.where(status: :published).where("floor_number > ?", last_read_floor).count
    end

    scope :with_unread_for, ->(user) {
      joins(:topic)
        .where(user: user, forum_topics: { status: :published })
        .where(<<~SQL.squish)
          EXISTS (
            SELECT 1 FROM forum_posts
            WHERE forum_posts.forum_topic_id = forum_read_states.forum_topic_id
              AND forum_posts.status = 'published'
              AND forum_posts.floor_number > forum_read_states.last_read_floor
          )
        SQL
        .order("forum_topics.last_posted_at DESC")
    }

    scope :unread_topics_count_for, ->(user) {
      with_unread_for(user).count
    }
  end
end
