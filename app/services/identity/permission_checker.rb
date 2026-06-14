# frozen_string_literal: true

module Identity
  class PermissionChecker < ApplicationService
    def initialize(user:, permission_key:)
      @user = user
      @permission_key = permission_key.to_s
    end

    def call
      allowed = Permission
        .joins(roles: :users)
        .where(users: { id: @user.id }, permissions: { key: @permission_key })
        .exists?

      ServiceResult.success(allowed: allowed)
    end
  end
end
