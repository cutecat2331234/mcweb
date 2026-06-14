# frozen_string_literal: true

module Community
  class Poll < ApplicationRecord
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    has_many :votes, class_name: "Community::PollVote", foreign_key: :forum_poll_id, dependent: :destroy

    validates :question, presence: true
    validates :options, length: { minimum: 2, maximum: 10 }

    def open?
      closes_at.nil? || closes_at > Time.current
    end

    def results
      counts = votes.group(:option_index).count
      options.each_with_index.map do |label, index|
        vote_count = counts[index] || 0
        { label: label, index: index, votes: vote_count }
      end
    end

    def total_votes
      votes.count
    end
  end
end
