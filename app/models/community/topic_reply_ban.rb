# frozen_string_literal: true

module Community
  class TopicReplyBan < ApplicationRecord
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :user
    belongs_to :created_by, class_name: "User"

    validates :user_id, uniqueness: { scope: :forum_topic_id }

    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    def active?
      expires_at.nil? || expires_at > Time.current
    end
  end
end
