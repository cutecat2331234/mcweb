# frozen_string_literal: true

module Community
  class TopicTag < ApplicationRecord
    belongs_to :topic, class_name: "Community::Topic", foreign_key: :forum_topic_id
    belongs_to :tag, class_name: "Community::Tag", foreign_key: :forum_tag_id

    validates :forum_topic_id, uniqueness: { scope: :forum_tag_id }
  end
end
