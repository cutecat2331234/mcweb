# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action -> { require_admin_module!("system") }
    before_action -> { require_permission("identity.roles.read") }
    before_action -> { require_permission("identity.roles.manage") },
      only: %i[create update destroy]
    before_action :set_role, only: %i[show update destroy]

    def index
      roles = Role.includes(:permissions).order(:name)

      render inertia: "Admin/Generic/Index", props: {
        title: t("mcweb.role_admin.title"),
        columns: [
          admin_column(:name, t("mcweb.role_admin.name"), link: true),
          admin_column(:key, t("mcweb.role_admin.key")),
          admin_column(:permissions, t("mcweb.role_admin.permission_count"))
        ],
        rows: roles.map do |role|
          admin_row(
            name: role.name,
            key: role.key,
            permissions: role.permissions.size,
            url: admin_role_path(role)
          )
        end
      }
    end

    def show
      render inertia: "Admin/Generic/Show", props: {
        title: @role.name,
        subtitle: @role.description,
        fields: [
          { label: t("mcweb.role_admin.key"), value: @role.key },
          {
            label: t("mcweb.role_admin.system_role"),
            value: @role.system_role? ? t("mcweb.labels.yes") : t("mcweb.labels.no")
          }
        ],
        sections: [
          {
            title: t("mcweb.role_admin.permissions"),
            items: @role.permissions.order(:key).map do |permission|
              {
                label: translated_permission_name(permission),
                value: permission.key
              }
            end
          }
        ],
        backUrl: admin_roles_path
      }
    end

    def create
      result = apply_role_mutation(
        :create,
        attributes: role_params,
        permissions_submitted: permission_ids_submitted?,
        permission_ids: requested_permission_ids
      )
      if result.success?
        redirect_to admin_role_path(result.value.fetch(:role)),
          notice: t("mcweb.flash.created", resource: t("mcweb.resources.role"))
      else
        redirect_to admin_roles_path, alert: service_error_message(result)
      end
    end

    def update
      result = apply_role_mutation(
        :update,
        role: @role,
        attributes: role_params,
        permissions_submitted: permission_ids_submitted?,
        permission_ids: requested_permission_ids
      )
      if result.success?
        redirect_to admin_role_path(@role), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.role"))
      else
        redirect_to admin_role_path(@role), alert: service_error_message(result)
      end
    end

    def destroy
      result = apply_role_mutation(:destroy, role: @role)
      if result.success?
        redirect_to admin_roles_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.role"))
      else
        redirect_to admin_role_path(@role), alert: service_error_message(result)
      end
    end

    private

    def set_role
      @role = Role.find(params[:id])
    end

    def role_params
      params.expect(role: %i[name key description])
    end

    def apply_role_mutation(operation, role: nil, attributes: {}, permission_ids: [],
                            permissions_submitted: false)
      Identity::ApplyRoleMutation.call(
        actor: current_user,
        operation:,
        role:,
        attributes:,
        permission_ids:,
        permissions_submitted:
      )
    end

    def requested_permission_ids
      Array(params.dig(:role, :permission_ids))
    end

    def permission_ids_submitted?
      params.fetch(:role, {}).key?(:permission_ids)
    end

    def translated_permission_name(permission)
      catalog_entry = Identity::PermissionCatalog.find(permission.key)
      return permission.name unless catalog_entry

      I18n.t(
        "#{catalog_entry.i18n_key}.name",
        default: permission.name
      )
    end
  end
end
