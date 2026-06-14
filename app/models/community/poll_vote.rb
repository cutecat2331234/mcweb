# frozen_string_literal: true

module Community
  class PollVote < ApplicationRecord
    belongs_to :poll, class_name: "Community::Poll", foreign_key: :forum_poll_id
    belongs_to :user

    validates :option_index, presence: true
    validates :user_id, uniqueness: { scope: :forum_poll_id }
    validate :option_index_in_range

    private

    def option_index_in_range
      return if poll && option_index.present? && option_index.between?(0, poll.options.size - 1)

      errors.add(:option_index, "is invalid")
    end
  end
end
