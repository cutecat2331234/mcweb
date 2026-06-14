# frozen_string_literal: true

module Community
  class TopicStaffNote < ApplicationRecord
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :author, class_name: "User"

    validates :body, presence: true
  end
end
