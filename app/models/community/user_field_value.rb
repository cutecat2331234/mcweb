# frozen_string_literal: true

module Community
  class UserFieldValue < ApplicationRecord
    self.table_name = "forum_user_field_values"

    belongs_to :user
    belongs_to :definition, class_name: "Community::UserFieldDefinition", foreign_key: :forum_user_field_definition_id

    validates :forum_user_field_definition_id, uniqueness: { scope: :user_id }
  end
end
