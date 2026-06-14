# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action -> { require_permission("system.settings.manage") }
    before_action :set_role, only: %i[show edit update destroy]

    def index
      @roles = Role.includes(:permissions).order(:name)
    end

    def show
    end

    def new
      @role = Role.new
    end

    def create
      @role = Role.new(role_params)

      if @role.save
        sync_permissions!
        Administration::AuditLogger.call(actor: current_user, action: "admin.role_created", resource: @role)
        redirect_to admin_role_path(@role), notice: "Role created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @role.update(role_params)
        sync_permissions!
        Administration::AuditLogger.call(actor: current_user, action: "admin.role_updated", resource: @role)
        redirect_to admin_role_path(@role), notice: "Role updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to admin_roles_path, alert: "System roles cannot be deleted." if @role.system_role?

      @role.destroy!
      Administration::AuditLogger.call(actor: current_user, action: "admin.role_deleted", resource: @role)
      redirect_to admin_roles_path, notice: "Role deleted."
    end

    private

    def set_role
      @role = Role.find_by!(key: params[:id])
    end

    def role_params
      params.expect(role: %i[name key system_role])[:role]
    end

    def sync_permissions!
      permission_ids = Array(params.dig(:role, :permission_ids)).reject(&:blank?).map(&:to_i)
      @role.permission_ids = permission_ids
    end
  end
end
