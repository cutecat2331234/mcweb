# frozen_string_literal: true

require "set"

module Identity
  class AccountAccess < ApplicationService
    ADMIN_MODULES = PermissionCatalog.active_entries
      .select(&:admin_module)
      .group_by(&:admin_module)
      .transform_values do |entries|
        entries.map(&:key).sort.map { |permission| permission.dup.freeze }.freeze
      end
      .freeze

    def initialize(user:, module_key: nil)
      @user = user
      @module_key = module_key
    end

    def call
      unless @user
        return ServiceResult.failure(
          error: "authentication_required",
          code: "authentication_required"
        )
      end

      ServiceResult.success(
        account_type: @user.account_type,
        can_access_admin: can_access_admin?,
        admin_modules: granted_modules,
        can_edit_others_posts: can_edit_others_posts?,
        can_edit_others_topics: can_edit_others_topics?
      )
    end

    def self.can_access_admin?(user)
      return false unless user

      case user.account_type
      when "owner", "admin"
        user.permission?("admin.access")
      when "staff"
        user.permission?("admin.access") &&
          user.admin_module_grants.where(module_key: admin_module_keys).exists?
      else
        # 向后兼容：已有 admin.access 角色的会员仍可进后台
        user.permission?("admin.access")
      end
    end

    def self.admin_modules
      ADMIN_MODULES
    end

    def self.admin_module_keys
      ADMIN_MODULES.keys.sort.freeze
    end

    def self.effective_permission_keys(user)
      return [] unless user
      return PermissionCatalog.assignable_keys.sort if user.account_owner?

      assignable_keys = PermissionCatalog.assignable_keys.to_set
      user.authorization_permission_keys.to_a
        .uniq
        .select { |permission_key| assignable_keys.include?(permission_key) }
        .sort
    end

    def self.allowed_module_keys(
      user,
      admin_access_checked: false,
      effective_permission_keys: nil
    )
      return [] unless user
      return [] unless admin_access_checked || can_access_admin?(user)
      return admin_module_keys if user.account_type.in?(%w[owner admin])

      if user.account_type == "staff"
        return user.admin_module_grants
          .where(module_key: admin_module_keys)
          .pluck(:module_key)
          .uniq
          .sort
      end

      effective_permissions =
        Array(effective_permission_keys || self.effective_permission_keys(user)).to_set
      admin_modules.filter_map do |module_key, permission_keys|
        module_key if permission_keys.any? { |permission_key| effective_permissions.include?(permission_key) }
      end.sort
    end

    def self.module_allowed?(user, module_key)
      return false unless user

      key = module_key.to_s
      permissions = admin_modules[key]
      return false unless permissions
      return true if user.account_type.in?(%w[owner admin])

      if user.account_type == "staff"
        return user.admin_module_grants.exists?(module_key: key)
      end

      permissions.any? { |key| user.permission?(key) }
    end

    private

    def can_access_admin?
      @can_access_admin ||= self.class.can_access_admin?(@user)
    end

    def granted_modules
      self.class.allowed_module_keys(
        @user,
        admin_access_checked: can_access_admin?
      )
    end

    def can_edit_others_posts?
      @user.permission?("forum.posts.edit_others") || @user.permission?("forum.topics.lock")
    end

    def can_edit_others_topics?
      @user.permission?("forum.topics.edit_others") || @user.permission?("forum.topics.lock")
    end
  end
end
