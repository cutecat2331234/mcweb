class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions,
           through: :role_permissions,
           after_remove: :bump_user_permission_versions_after_permission_removal
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :key, presence: true, uniqueness: true,
                  format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true

  scope :system_roles, -> { where(system_role: true) }
  scope :custom_roles, -> { where(system_role: false) }

  def grant_permission!(permission)
    Identity::PermissionMutationLock.with_exclusive do
      permission = Permission.find_by!(key: permission) if permission.is_a?(String)
      RolePermission.find_or_create_by!(role: self, permission:)
    end
  end

  def revoke_permission!(permission)
    Identity::PermissionMutationLock.with_exclusive do
      permission = Permission.find_by!(key: permission) if permission.is_a?(String)
      RolePermission.where(role: self, permission:).destroy_all
    end
  end

  private

  # Assigning through #permissions deletes join rows without running the
  # RolePermission destroy callback. Keep every affected user's cache version
  # in sync with that association-level mutation path.
  def bump_user_permission_versions_after_permission_removal(_permission)
    Identity::PermissionVersion.bump_role_users!(id)
  end
end
