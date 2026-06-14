class Role < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :permissions, through: :role_permissions
  has_many :user_roles, dependent: :destroy
  has_many :users, through: :user_roles

  validates :key, presence: true, uniqueness: true,
                  format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validates :name, presence: true

  scope :system_roles, -> { where(system_role: true) }
  scope :custom_roles, -> { where(system_role: false) }

  def grant_permission!(permission)
    permission = Permission.find_by!(key: permission) if permission.is_a?(String)
    permissions << permission unless permissions.include?(permission)
  end

  def revoke_permission!(permission)
    permission = Permission.find_by!(key: permission) if permission.is_a?(String)
    permissions.delete(permission)
  end
end
