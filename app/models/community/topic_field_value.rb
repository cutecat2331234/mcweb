# frozen_string_literal: true

module Community
  class TopicFieldValue < ApplicationRecord
    self.table_name = "forum_topic_field_values"

    belongs_to :topic,
      class_name: "Community::Topic",
      foreign_key: :forum_topic_id,
      inverse_of: :topic_field_values
    belongs_to :definition,
      class_name: "Community::TopicFieldDefinition",
      foreign_key: :forum_topic_field_definition_id,
      inverse_of: :values

    validates :value, presence: true
    validates :forum_topic_id, uniqueness: { scope: :forum_topic_field_definition_id }
  end
end
