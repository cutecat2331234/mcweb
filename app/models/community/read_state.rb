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

    def unread_count
      topic.replies_count - last_read_floor
    end
  end
end
