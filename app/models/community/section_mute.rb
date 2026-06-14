# frozen_string_literal: true

module Community
  class SectionMute < ApplicationRecord
    belongs_to :user
    belongs_to :section, class_name: "Community::Section", foreign_key: :forum_section_id

    validates :user_id, uniqueness: { scope: :forum_section_id }
  end
end
