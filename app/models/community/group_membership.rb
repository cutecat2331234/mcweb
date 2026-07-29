# frozen_string_literal: true

module Community
  class GroupMembership < ApplicationRecord
    self.table_name = "community_group_memberships"

    belongs_to :user
    belongs_to :user_group, class_name: "Community::UserGroup", foreign_key: :community_user_group_id

    validates :user_id, uniqueness: { scope: :community_user_group_id }

    scope :primary, -> { where(is_primary: true) }

    after_create :bump_permission_version
    after_destroy :bump_permission_version

    private

    def bump_permission_version
      Identity::PermissionVersion.bump_users!([ user_id ])
    end
  end
end
