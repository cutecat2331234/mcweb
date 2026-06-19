# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_role, only: %i[show edit update destroy]

    def index
      roles = Role.includes(:permissions).order(:name)

      render inertia: "Admin/Generic/Index", props: {
        title: "角色",
        columns: [
          admin_column(:name, "名称", link: true),
          admin_column(:key, "标识"),
          admin_column(:permissions, "权限数")
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
          { label: "标识", value: @role.key },
          { label: "系统角色", value: @role.system_role? ? "是" : "否" }
        ],
        sections: [
          {
            title: "权限",
            items: @role.permissions.order(:key).map do |permission|
              { label: permission.key, value: permission.name }
            end
          }
        ],
        backUrl: admin_roles_path
      }
    end

    def new
      @role = Role.new
    end

    def create
      @role = Role.new(role_params)

      if @role.save
        sync_permissions!
        Administration::AuditLogger.call(actor: current_user, action: "admin.role_created", resource: @role)
        redirect_to admin_role_path(@role), notice: t("mcweb.flash.created", resource: t("mcweb.resources.role"))
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      return redirect_to admin_roles_path, alert: t("mcweb.flash.system_role_immutable") if @role.system_role?

      if @role.update(role_params)
        sync_permissions!
        Administration::AuditLogger.call(actor: current_user, action: "admin.role_updated", resource: @role)
        redirect_to admin_role_path(@role), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.role"))
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to admin_roles_path, alert: t("mcweb.flash.system_role_undeletable") if @role.system_role?

      @role.destroy!
      Administration::AuditLogger.call(actor: current_user, action: "admin.role_deleted", resource: @role)
      redirect_to admin_roles_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.role"))
    end

    private

    def set_role
      @role = Role.find_by!(key: params[:id])
    end

    def role_params
      params.expect(role: %i[name key description])[:role]
    end

    def sync_permissions!
      permission_ids = Array(params.dig(:role, :permission_ids)).reject(&:blank?).map(&:to_i)
      @role.permission_ids = permission_ids
    end
  end
end
