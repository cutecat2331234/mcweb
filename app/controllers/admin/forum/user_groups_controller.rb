# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style user group management (phase 1: groups + permission keys).
    class UserGroupsController < BaseController
      MEMBER_PAGE_SIZE = 20

      skip_before_action :require_forum_admin_module!
      before_action -> { require_admin_module!("identity") }
      before_action -> { require_permission("identity.groups.read") }
      before_action -> { require_permission("identity.groups.manage") },
        only: %i[new create update destroy]
      before_action -> { require_permission("identity.groups.members.assign") },
        only: %i[add_member remove_member set_primary]
      before_action :set_group, only: %i[edit update destroy]

      def index
        groups = ::Community::UserGroup.ordered
        membership_counts = ::Community::GroupMembership
          .where(community_user_group_id: groups.select(:id))
          .group(:community_user_group_id)
          .count
        can_manage_groups = identity_permission_allowed?("identity.groups.manage")

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("user_groups.title"),
          subtitle: forum_t("user_groups.description"),
          columns: [
            admin_column(:name, forum_t("user_groups.col_name"), link: true),
            admin_column(:priority, forum_t("user_groups.col_priority")),
            admin_column(:members, forum_t("user_groups.col_members")),
            admin_column(:primary_default, forum_t("user_groups.col_primary_default"))
          ],
          rows: groups.map do |group|
            admin_row(
              name: group.name,
              priority: group.priority,
              members: membership_counts.fetch(group.id, 0),
              primary_default: forum_yes_no(group.is_primary_default),
              url: edit_admin_forum_user_group_path(group)
            )
          end,
          actions: can_manage_groups ? [
            { label: forum_t("user_groups.action_new"), href: new_admin_forum_user_group_path }
          ] : []
        }
      end

      def new
        render inertia: "Admin/Forum/UserGroups/Form", props: form_props(::Community::UserGroup.new)
      end

      def create
        result = apply_group_mutation(:create, attributes: group_attributes)
        group = result.value&.dig(:group) || ::Community::UserGroup.new(group_attributes)
        if result.success?
          redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_created")
        else
          flash.now[:alert] = service_error_message(result)
          render inertia: "Admin/Forum/UserGroups/Form", props: form_props(group), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/UserGroups/Form", props: form_props(@group, editing: true)
      end

      def update
        result = apply_group_mutation(:update, group: @group, attributes: group_attributes)
        group = result.value&.dig(:group) || @group
        if result.success?
          redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_updated")
        else
          flash.now[:alert] = service_error_message(result)
          render inertia: "Admin/Forum/UserGroups/Form", props: form_props(group, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        result = apply_group_mutation(:destroy, group: @group)
        if result.success?
          redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_deleted")
        else
          redirect_to edit_admin_forum_user_group_path(@group), alert: service_error_message(result)
        end
      end

      def add_member
        group = ::Community::UserGroup.find(params[:id])
        user = ::User.find_by("LOWER(username) = ?", params[:username].to_s.strip.downcase)
        return redirect_to edit_admin_forum_user_group_path(group), alert: t("mcweb.flash.user_group_member_not_found") if user.nil?

        result = apply_group_mutation(:add_member, group: group, user: user)
        if result.success?
          redirect_to edit_admin_forum_user_group_path(group), notice: t("mcweb.flash.user_group_member_added")
        else
          redirect_to edit_admin_forum_user_group_path(group), alert: service_error_message(result)
        end
      end

      def remove_member
        group = ::Community::UserGroup.find(params[:id])
        user = ::User.find_by(id: params[:user_id])
        return redirect_to edit_admin_forum_user_group_path(group), alert: t("mcweb.flash.user_group_member_not_found") if user.nil?

        result = apply_group_mutation(:remove_member, group: group, user: user)
        if result.success?
          redirect_to edit_admin_forum_user_group_path(group), notice: t("mcweb.flash.user_group_member_removed")
        else
          redirect_to edit_admin_forum_user_group_path(group), alert: service_error_message(result)
        end
      end

      def set_primary
        group = ::Community::UserGroup.find(params[:id])
        user = ::User.find_by(id: params[:user_id])
        return redirect_to edit_admin_forum_user_group_path(group), alert: t("mcweb.flash.user_group_member_not_found") if user.nil?

        result = apply_group_mutation(:set_primary, group: group, user: user)
        if result.success?
          redirect_to edit_admin_forum_user_group_path(group), notice: t("mcweb.flash.user_group_primary_set")
        else
          redirect_to edit_admin_forum_user_group_path(group), alert: service_error_message(result)
        end
      end

      private

      def set_group
        @group = ::Community::UserGroup.find(params[:id])
      end

      def group_attributes
        attributes = {
          name: params.dig(:user_group, :name).to_s.strip,
          color_hex: params.dig(:user_group, :color_hex).presence,
          priority: params.dig(:user_group, :priority).to_i,
          banner_text: params.dig(:user_group, :banner_text).presence,
          is_primary_default: ActiveModel::Type::Boolean.new.cast(params.dig(:user_group, :is_primary_default))
        }
        if params.fetch(:user_group, {}).key?(:permissions)
          attributes[:permissions] = params.dig(:user_group, :permissions)
        end
        attributes
      end

      def apply_group_mutation(operation, group: nil, user: nil, attributes: {})
        Identity::ApplyGroupMutation.call(
          actor: current_user,
          operation: operation,
          group: group,
          user: user,
          attributes: attributes
        )
      end

      def identity_permission_allowed?(permission_key)
        result = Identity::PermissionChecker.call(
          user: current_user,
          permission_key: permission_key
        )
        result.success? && result.value[:allowed]
      end

      def form_props(group, editing: false)
        can_manage_group = identity_permission_allowed?("identity.groups.manage")
        can_manage_members = identity_permission_allowed?("identity.groups.members.assign")
        can_manage_permissions = can_manage_group &&
          identity_permission_allowed?("identity.groups.permissions.manage")
        grantable_permission_keys = grantable_permission_keys_for_current_user
        can_add_members = editing &&
          can_manage_members &&
          permission_keys_grantable?(group.permission_keys, grantable_permission_keys)
        member_pagination = editing ? member_pagination(group) : {
          members: [],
          member_page: 1,
          member_total: 0
        }
        delete_blocked =
          if editing && can_manage_group
            delete_blocked_reason(
              group,
              can_manage_members:,
              can_manage_permissions:
            )
          end
        form_title =
          if editing && !can_manage_group
            forum_t("user_groups.form_view")
          elsif editing
            forum_t("user_groups.form_edit")
          else
            forum_t("user_groups.form_new")
          end
        submit_url =
          if can_manage_group
            editing ? admin_forum_user_group_path(group) : admin_forum_user_groups_path
          end
        delete_url =
          if editing && can_manage_group && delete_blocked.nil?
            admin_forum_user_group_path(group)
          end

        {
          title: form_title,
          user_group: {
            name: group.name || "",
            color_hex: group.color_hex || "",
            priority: group.priority || 0,
            banner_text: group.banner_text || "",
            is_primary_default: group.is_primary_default.nil? ? false : group.is_primary_default,
            permissions: group.permission_keys
          },
          permissionCatalog: serialized_permission_catalog(
            group,
            grantable_permission_keys:
          ),
          grantablePermissionKeys: grantable_permission_keys,
          members: member_pagination.fetch(:members),
          memberPage: member_pagination.fetch(:member_page),
          memberPageSize: MEMBER_PAGE_SIZE,
          memberTotal: member_pagination.fetch(:member_total),
          memberPageUrl: editing ? edit_admin_forum_user_group_path(group) : nil,
          showMembers: editing,
          canManageGroup: can_manage_group,
          canManageMembers: can_manage_members,
          canManagePermissions: can_manage_permissions,
          canAddMembers: can_add_members,
          addMemberUrl: can_add_members ? add_member_admin_forum_user_group_path(group) : nil,
          submitUrl: submit_url,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_user_groups_path,
          deleteUrl: delete_url,
          deleteBlocked: delete_blocked
        }
      end

      def member_pagination(group)
        total = group.group_memberships.count
        max_page = [ (total.to_f / MEMBER_PAGE_SIZE).ceil, 1 ].max
        requested_page = params[:member_page].to_i
        requested_page = 1 if requested_page < 1
        page = [ requested_page, max_page ].min

        {
          members: serialize_members(group, page: page),
          member_page: page,
          member_total: total
        }
      end

      def serialize_members(group, page:)
        can_manage_members = identity_permission_allowed?("identity.groups.members.assign")

        group.group_memberships
          .includes(:user)
          .order(:id)
          .offset((page - 1) * MEMBER_PAGE_SIZE)
          .limit(MEMBER_PAGE_SIZE)
          .filter_map do |membership|
            next unless membership.user

            {
              user_id: membership.user_id,
              username: membership.user.username,
              is_primary: membership.is_primary,
              remove_url: can_manage_members ? remove_member_admin_forum_user_group_path(group, user_id: membership.user_id) : nil,
              set_primary_url: can_manage_members ? set_primary_admin_forum_user_group_path(group, user_id: membership.user_id) : nil
            }
          end
      end

      def grantable_permission_keys_for_current_user
        assignable_keys = Identity::PermissionCatalog.assignable_keys
        return assignable_keys if current_user.account_owner?

        actor_permission_keys =
          (current_user.permissions.pluck(:key) + current_user.group_permission_keys).uniq
        assignable_keys & actor_permission_keys
      end

      def permission_keys_grantable?(permission_keys, grantable_permission_keys)
        (Array(permission_keys).map(&:to_s) - grantable_permission_keys).empty?
      end

      def delete_blocked_reason(group, can_manage_members:, can_manage_permissions:)
        members_blocked = group.group_memberships.exists? && !can_manage_members
        permissions_blocked = group.permission_keys.any? && !can_manage_permissions

        return "members_and_permissions" if members_blocked && permissions_blocked
        return "members" if members_blocked
        "permissions" if permissions_blocked
      end

      def serialized_permission_catalog(group, grantable_permission_keys:)
        current_permission_keys = group.permission_keys

        catalog = Identity::PermissionCatalog.grouped_json(locale: I18n.locale).map do |domain|
          domain.merge(
            permissions: domain.fetch(:permissions).map do |permission|
              key = permission.fetch(:key)
              grantable = grantable_permission_keys.include?(key)
              permission.merge(
                grantable: grantable,
                delegable: grantable || current_permission_keys.include?(key)
              )
            end
          )
        end
        catalog_keys = catalog.flat_map { |domain| domain.fetch(:permissions).pluck(:key) }
        orphaned_keys = current_permission_keys - catalog_keys
        if orphaned_keys.any?
          catalog << {
            key: "legacy",
            name: t("mcweb.permission_catalog.legacy_group"),
            permissions: orphaned_keys.sort.map do |key|
              {
                key: key,
                name: key,
                description: t("mcweb.permission_catalog.legacy_description"),
                grantable: false,
                delegable: true
              }
            end
          }
        end
        catalog
      end
    end
  end
end
