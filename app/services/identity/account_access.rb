# frozen_string_literal: true

module Identity
  class AccountAccess < ApplicationService
    ADMIN_MODULES = {
      "forum" => %w[forum.sections.manage forum.topics.lock forum.topics.move forum.users.mute forum.users.warn forum.badges.manage forum.tags.manage forum.posts.edit_others forum.topics.edit_others],
      "store" => %w[store.products.manage store.orders.read store.orders.refund store.questions.answer store.questions.manage],
      "minecraft" => %w[minecraft.servers.manage minecraft.fulfillments.retry],
      "system" => %w[system.settings.manage system.jobs.read system.jobs.retry system.audit.read],
      "website" => %w[website.pages.read website.pages.edit website.pages.publish website.templates.manage]
    }.freeze

    def initialize(user:, module_key: nil)
      @user = user
      @module_key = module_key
    end

    def call
      return ServiceResult.failure(error: "未登录") unless @user

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
        user.permission?("admin.access") && user.admin_module_grants.exists?
      else
        # 向后兼容：已有 admin.access 角色的会员仍可进后台
        user.permission?("admin.access")
      end
    end

    def self.module_allowed?(user, module_key)
      return false unless user
      return true if user.account_type.in?(%w[owner admin])

      if user.account_type == "staff"
        return user.admin_module_grants.exists?(module_key: module_key)
      end

      permissions = ADMIN_MODULES[module_key.to_s] || []
      permissions.any? { |key| user.permission?(key) }
    end

    private

    def can_access_admin?
      self.class.can_access_admin?(@user)
    end

    def granted_modules
      case @user.account_type
      when "owner", "admin"
        ADMIN_MODULES.keys
      when "staff"
        @user.admin_module_grants.pluck(:module_key)
      else
        []
      end
    end

    def can_edit_others_posts?
      @user.permission?("forum.posts.edit_others") || @user.permission?("forum.topics.lock")
    end

    def can_edit_others_topics?
      @user.permission?("forum.topics.edit_others") || @user.permission?("forum.topics.lock")
    end
  end
end
