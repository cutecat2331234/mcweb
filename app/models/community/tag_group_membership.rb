# frozen_string_literal: true

module Community
  class TagGroupMembership < ApplicationRecord
    belongs_to :tag_group, class_name: "Community::TagGroup", foreign_key: :forum_tag_group_id
    belongs_to :tag, class_name: "Community::Tag", foreign_key: :forum_tag_id

    validates :forum_tag_id, uniqueness: { scope: :forum_tag_group_id }
  end
end
