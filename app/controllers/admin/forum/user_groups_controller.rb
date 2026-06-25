# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style user group management (phase 1: groups + permission keys).
    class UserGroupsController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_group, only: %i[edit update destroy]

      def index
        groups = ::Community::UserGroup.ordered

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
              members: group.group_memberships.count,
              primary_default: forum_yes_no(group.is_primary_default),
              url: edit_admin_forum_user_group_path(group)
            )
          end,
          actions: [ { label: forum_t("user_groups.action_new"), href: new_admin_forum_user_group_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/UserGroups/Form", props: form_props(::Community::UserGroup.new)
      end

      def create
        group = ::Community::UserGroup.new(group_attributes)
        if group.save
          redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_created")
        else
          render inertia: "Admin/Forum/UserGroups/Form", props: form_props(group), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/UserGroups/Form", props: form_props(@group, editing: true)
      end

      def update
        if @group.update(group_attributes)
          redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_updated")
        else
          render inertia: "Admin/Forum/UserGroups/Form", props: form_props(@group, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @group.destroy!
        redirect_to admin_forum_user_groups_path, notice: t("mcweb.flash.user_group_deleted")
      end

      private

      def set_group
        @group = ::Community::UserGroup.find(params[:id])
      end

      def group_attributes
        {
          name: params.dig(:user_group, :name).to_s.strip,
          color_hex: params.dig(:user_group, :color_hex).presence,
          priority: params.dig(:user_group, :priority).to_i,
          banner_text: params.dig(:user_group, :banner_text).presence,
          is_primary_default: ActiveModel::Type::Boolean.new.cast(params.dig(:user_group, :is_primary_default)),
          permissions: parse_permission_keys(params.dig(:user_group, :permissions))
        }
      end

      def parse_permission_keys(value)
        value.to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?).uniq
      end

      def form_props(group, editing: false)
        {
          title: editing ? forum_t("user_groups.form_edit") : forum_t("user_groups.form_new"),
          user_group: {
            name: group.name || "",
            color_hex: group.color_hex || "",
            priority: group.priority || 0,
            banner_text: group.banner_text || "",
            is_primary_default: group.is_primary_default.nil? ? false : group.is_primary_default,
            permissions: group.permission_keys.join("\n")
          },
          availablePermissions: Permission.order(:key).pluck(:key),
          submitUrl: editing ? admin_forum_user_group_path(group) : admin_forum_user_groups_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_user_groups_path,
          deleteUrl: editing ? admin_forum_user_group_path(group) : nil
        }
      end
    end
  end
end
