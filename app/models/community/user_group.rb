# frozen_string_literal: true

module Community
  # XenForo-style user group: display styling (name, color, banner) + a set of
  # permission keys. Users have one primary group + any number of secondary
  # groups (via GroupMembership). Effective permissions are the union across a
  # user's groups (enforcement wired in a later phase).
  class UserGroup < ApplicationRecord
    self.table_name = "community_user_groups"

    has_many :group_memberships, class_name: "Community::GroupMembership",
             foreign_key: :community_user_group_id, dependent: :destroy
    has_many :users, through: :group_memberships

    validates :name, presence: true, length: { maximum: 100 }
    validates :priority, numericality: { only_integer: true }

    scope :ordered, -> { order(priority: :desc, name: :asc) }
    scope :primary_defaults, -> { where(is_primary_default: true) }

    def permission_keys
      Array(permissions).map(&:to_s)
    end

    # Union of permission keys across the given user's groups.
    def self.permission_keys_for(user)
      return [] unless user

      where(id: Community::GroupMembership.where(user_id: user.id).select(:community_user_group_id))
        .flat_map(&:permission_keys)
        .uniq
    end
  end
end
