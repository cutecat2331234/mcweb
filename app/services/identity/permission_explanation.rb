# frozen_string_literal: true

require "set"

module Identity
  class PermissionExplanation < ApplicationService
    def initialize(user:, locale: I18n.locale)
      @user = user
      @locale = locale
    end

    def call
      return ServiceResult.failure(error: "user_not_found", code: "not_found") unless @user

      @user.reload

      roles = @user.roles.includes(:permissions).order(:name, :id).to_a
      memberships = @user.group_memberships
        .includes(:user_group)
        .sort_by { |membership| [ -membership.user_group.priority, membership.user_group.name, membership.id ] }
      granted_keys = (
        roles.flat_map { |role| role.permissions.map(&:key) } +
        memberships.flat_map { |membership| membership.user_group.permission_keys }
      ).to_set
      eligible = @user.session_eligible?

      categories = PermissionCatalog.grouped_json(locale: @locale).map do |category|
        {
          key: category.fetch(:key),
          name: category.fetch(:name),
          permissions: category.fetch(:permissions).map do |permission|
            explain_permission(
              permission:,
              roles:,
              memberships:,
              granted_keys:,
              eligible:
            )
          end
        }
      end

      permissions = categories.flat_map { |category| category.fetch(:permissions) }
      ServiceResult.success(
        user: {
          public_id: @user.public_id,
          username: @user.username,
          display_name: @user.display_name,
          status: @user.status,
          account_type: @user.account_type,
          eligible:,
          permission_version: @user.permission_version
        },
        summary: {
          total: permissions.size,
          allowed: permissions.count { |permission| permission.fetch(:allowed) },
          denied: permissions.count { |permission| !permission.fetch(:allowed) }
        },
        categories:
      )
    end

    private

    def explain_permission(permission:, roles:, memberships:, granted_keys:, eligible:)
      key = permission.fetch(:key)
      sources = permission_sources(key:, roles:, memberships:)
      granted = @user.account_owner? || granted_keys.include?(key)
      allowed = eligible && granted

      {
        key:,
        name: permission.fetch(:name),
        description: permission.fetch(:description),
        allowed:,
        eligible:,
        reason: decision_reason(granted:, eligible:, sources:),
        sources:
      }
    end

    def permission_sources(key:, roles:, memberships:)
      sources = []
      if @user.account_owner?
        sources << {
          type: "account",
          name: I18n.t("mcweb.permission_explanation.sources.owner", locale: @locale)
        }
      end

      roles.each do |role|
        next unless role.permissions.any? { |permission| permission.key == key }

        sources << {
          type: "role",
          id: role.id,
          name: role.name
        }
      end

      memberships.each do |membership|
        group = membership.user_group
        next unless group.permission_keys.include?(key)

        sources << {
          type: "group",
          id: group.id,
          name: group.name,
          primary: membership.is_primary?
        }
      end
      sources
    end

    def decision_reason(granted:, eligible:, sources:)
      return "account_deleted" if @user.deleted?
      return "account_banned" if @user.banned?
      return "account_ineligible" unless eligible
      return "owner_override" if @user.account_owner?
      return "granted_by_role_and_group" if source_types(sources).superset?(Set["role", "group"])
      return "granted_by_role" if source_types(sources).include?("role")
      return "granted_by_group" if source_types(sources).include?("group")
      return "granted_by_core_policy" if granted

      "not_granted"
    end

    def source_types(sources)
      sources.map { |source| source.fetch(:type) }.to_set
    end
  end
end
