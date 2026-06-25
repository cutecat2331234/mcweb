# frozen_string_literal: true

module Community
  # XenForo-style "user title ladder": automatic titles awarded by post count.
  # A user's effective title is their custom `forum_title` if set, otherwise the
  # highest ladder rung whose `min_posts` they have reached.
  class UserTitleLadder < ApplicationRecord
    self.table_name = "forum_user_title_ladders"

    validates :title, presence: true, length: { maximum: 100 }
    validates :min_posts, presence: true,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :ordered, -> { order(min_posts: :asc) }

    # Rungs ordered highest-first, as [min_posts, title] pairs — load once and
    # resolve many users in Ruby to avoid per-user queries.
    def self.rungs_desc
      order(min_posts: :desc).pluck(:min_posts, :title)
    end

    def self.title_for(post_count)
      count = post_count.to_i
      rungs_desc.find { |min_posts, _| min_posts <= count }&.last
    end
  end
end
