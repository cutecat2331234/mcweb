class RolePermission < ApplicationRecord
  belongs_to :role
  belongs_to :permission

  validates :role_id, uniqueness: { scope: :permission_id }

  after_create :bump_permission_versions
  after_destroy :bump_permission_versions

  private

  def bump_permission_versions
    Identity::PermissionVersion.bump_role_users!(role_id)
  end
end
