# frozen_string_literal: true

module Community
  class Bookmark < ApplicationRecord
    belongs_to :user
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id

    validates :user_id, uniqueness: { scope: :forum_topic_id }

    def self.toggle!(user, topic)
      bookmark = find_by(user: user, topic: topic)
      if bookmark
        bookmark.destroy!
        false
      else
        create!(user: user, topic: topic)
        true
      end
    end
  end
end
