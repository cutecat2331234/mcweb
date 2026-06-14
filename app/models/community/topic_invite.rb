# frozen_string_literal: true

module Community
  class TopicInvite < ApplicationRecord
    self.table_name = "forum_topic_invites"

    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :user
    belongs_to :invited_by, class_name: "User"

    validates :user_id, uniqueness: { scope: :forum_topic_id }
  end
end
