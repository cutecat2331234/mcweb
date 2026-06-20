# frozen_string_literal: true

module Community
  class SectionModerator < ApplicationRecord
    self.table_name = "forum_section_moderators"

    belongs_to :section, class_name: "Community::Section", foreign_key: :forum_section_id
    belongs_to :user

    validates :forum_section_id, uniqueness: { scope: :user_id }
  end
end
