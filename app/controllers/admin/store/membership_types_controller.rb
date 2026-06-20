# frozen_string_literal: true

module Admin
  module Store
    class MembershipTypesController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_membership_type, only: %i[show edit update]

      def index
        types = ::Commerce::MembershipType.by_display_priority

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.membership_types.title"),
          columns: [
            admin_column(:name, t("mcweb.admin.store.membership_types.col_name"), link: true),
            admin_column(:slug, t("mcweb.admin.store.membership_types.col_slug")),
            admin_column(:duration_mode, t("mcweb.admin.store.membership_types.col_duration")),
            admin_column(:active, t("mcweb.admin.store.membership_types.col_status"))
          ],
          rows: types.map do |type|
            admin_row(
              name: type.name,
              slug: type.slug,
              duration_mode: membership_duration_label(type),
              active: membership_active_label(type),
              url: admin_store_membership_type_path(type)
            )
          end,
          actions: [ { label: t("mcweb.admin.store.membership_types.new"), href: new_admin_store_membership_type_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @membership_type.name,
          subtitle: @membership_type.slug,
          fields: [
            { label: t("mcweb.admin.store.membership_types.field_description"), value: @membership_type.description.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.membership_types.field_icon"), value: @membership_type.icon.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.membership_types.field_color"), value: @membership_type.color.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.membership_types.field_duration"), value: membership_duration_label(@membership_type) },
            { label: t("mcweb.admin.store.membership_types.field_game_permission"), value: game_permission_label(@membership_type) },
            { label: t("mcweb.admin.store.membership_types.field_game_permission_mode"), value: game_permission_mode_label(@membership_type.game_permission_mode) },
            { label: t("mcweb.admin.store.membership_types.field_luckperms_group"), value: @membership_type.luckperms_group.presence || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.membership_types.field_display_priority"), value: @membership_type.display_priority.to_s },
            { label: t("mcweb.admin.store.membership_types.field_grant_commands"), value: format_commands(@membership_type.grant_commands) },
            { label: t("mcweb.admin.store.membership_types.field_revoke_commands"), value: format_commands(@membership_type.revoke_commands) },
            { label: t("mcweb.admin.store.membership_types.col_status"), value: membership_active_label(@membership_type) }
          ],
          backUrl: admin_store_membership_types_path,
          actions: [ { label: t("mcweb.admin.store.action_edit"), href: edit_admin_store_membership_type_path(@membership_type) } ]
        }
      end

      def new
        render inertia: "Admin/Store/MembershipTypes/Form", props: form_props(::Commerce::MembershipType.new)
      end

      def create
        type = ::Commerce::MembershipType.new(membership_type_params)
        if type.save
          redirect_to admin_store_membership_type_path(type), notice: t("mcweb.flash.created", resource: t("mcweb.resources.membership_type"))
        else
          render inertia: "Admin/Store/MembershipTypes/Form", props: form_props(type), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Store/MembershipTypes/Form", props: form_props(@membership_type)
      end

      def update
        if @membership_type.update(membership_type_params)
          redirect_to admin_store_membership_type_path(@membership_type), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.membership_type"))
        else
          render inertia: "Admin/Store/MembershipTypes/Form", props: form_props(@membership_type), status: :unprocessable_entity
        end
      end

      private

      def set_membership_type
        @membership_type = ::Commerce::MembershipType.find(params[:id])
      end

      def membership_type_params
        permitted = params.require(:membership_type).permit(
          :slug, :name, :description, :color, :icon,
          :duration_mode, :duration_days, :luckperms_group,
          :game_permission_enabled, :game_permission_mode,
          :grant_commands, :revoke_commands,
          :display_priority, :active
        )
        parse_json_commands!(permitted, :grant_commands)
        parse_json_commands!(permitted, :revoke_commands)
        permitted
      end

      def parse_json_commands!(permitted, key)
        return unless permitted[key].is_a?(String)

        raw = permitted[key].strip
        permitted[key] = raw.present? ? JSON.parse(raw) : []
      rescue JSON::ParserError
        raise ActionController::BadRequest, t("mcweb.admin.store.membership_types.commands_json_invalid")
      end

      def form_props(type)
        {
          title: type.persisted? ? t("mcweb.admin.store.membership_types.edit") : t("mcweb.admin.store.membership_types.new"),
          membership_type: {
            id: type.id,
            slug: type.slug || "",
            name: type.name || "",
            description: type.description || "",
            color: type.color || "#6366f1",
            icon: type.icon || "",
            duration_mode: type.duration_mode || "fixed_days",
            duration_days: type.duration_days || 30,
            luckperms_group: type.luckperms_group || "",
            game_permission_enabled: type.game_permission_enabled.nil? ? true : type.game_permission_enabled,
            game_permission_mode: type.game_permission_mode || "website_managed",
            grant_commands: JSON.pretty_generate(type.grant_commands.presence || []),
            revoke_commands: JSON.pretty_generate(type.revoke_commands.presence || []),
            display_priority: type.display_priority || 0,
            active: type.active.nil? ? true : type.active
          },
          submitUrl: type.persisted? ? admin_store_membership_type_path(type) : admin_store_membership_types_path,
          method: type.persisted? ? "patch" : "post",
          backUrl: admin_store_membership_types_path
        }
      end

      def membership_duration_label(type)
        if type.permanent?
          t("mcweb.labels.duration_mode.permanent")
        else
          t("mcweb.admin.store.membership_types.duration_days", count: type.duration_days)
        end
      end

      def membership_active_label(type)
        type.active? ? t("mcweb.admin.store.membership_types.status_enabled") : t("mcweb.admin.store.membership_types.status_disabled")
      end

      def game_permission_label(type)
        type.game_permission_enabled? ? t("mcweb.admin.store.membership_types.game_permission_on") : t("mcweb.admin.store.membership_types.game_permission_off")
      end

      def game_permission_mode_label(mode)
        t("mcweb.labels.game_permission_mode.#{mode}", default: mode.to_s.humanize)
      end

      def format_commands(commands)
        return t("mcweb.labels.not_available") if commands.blank?

        commands.join("\n")
      end
    end
  end
end
