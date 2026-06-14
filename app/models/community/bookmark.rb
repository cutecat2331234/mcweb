# frozen_string_literal: true

module Community
  class Bookmark < ApplicationRecord
    belongs_to :user
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :post, class_name: "Community::Post", foreign_key: :forum_post_id, optional: true

    validates :user_id, uniqueness: { scope: :forum_topic_id }, if: -> { forum_post_id.nil? }
    validates :user_id, uniqueness: { scope: :forum_post_id }, if: -> { forum_post_id.present? }

    def self.toggle!(user, topic)
      bookmark = find_by(user: user, topic: topic, forum_post_id: nil)
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
