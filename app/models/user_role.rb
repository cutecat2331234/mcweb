class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role

  validates :user_id, uniqueness: { scope: :role_id }

  after_create :bump_permission_version
  after_destroy :bump_permission_version

  private

  def bump_permission_version
    Identity::PermissionVersion.bump_users!([ user_id ])
  end
end
