# frozen_string_literal: true

module Community
  class GroupMembership < ApplicationRecord
    self.table_name = "community_group_memberships"

    belongs_to :user
    belongs_to :user_group, class_name: "Community::UserGroup", foreign_key: :community_user_group_id

    validates :user_id, uniqueness: { scope: :community_user_group_id }

    scope :primary, -> { where(is_primary: true) }
  end
end
