# frozen_string_literal: true

module Admin
  class RolesController < BaseController
    before_action -> { require_admin_module!("system") }
    before_action -> { require_permission("identity.roles.read") }
    before_action -> { require_permission("identity.roles.manage") },
      only: %i[new create edit update destroy]
    before_action :set_role, only: %i[show edit update destroy]

    def index
      @pagy, roles = pagy(
        :offset,
        Role.includes(:permissions).order(:name),
        limit: 25
      )
      member_counts = UserRole
        .where(role_id: roles.map(&:id))
        .group(:role_id)
        .count

      render inertia: "Admin/Roles/Index", props: {
        title: t("mcweb.role_admin.title"),
        subtitle: t("mcweb.role_admin.subtitle"),
        canManage: can_manage_roles?,
        newUrl: can_manage_roles? ? new_admin_role_path : nil,
        roles: roles.map { |role| serialize_role_summary(role, member_counts:) },
        pagination: pagy_props(@pagy)
      }
    end

    def show
      render inertia: "Admin/Roles/Show", props: show_props(@role)
    end

    def new
      render inertia: "Admin/Roles/Form", props: form_props(Role.new)
    end

    def edit
      render inertia: "Admin/Roles/Form", props: form_props(@role, editing: true)
    end

    def create
      attributes = role_params
      selected_permission_ids = requested_permission_ids
      result = apply_role_mutation(
        :create,
        attributes:,
        permissions_submitted: permission_ids_submitted?,
        permission_ids: selected_permission_ids
      )
      if result.success?
        redirect_to admin_role_path(result.value.fetch(:role)),
          notice: t("mcweb.flash.created", resource: t("mcweb.resources.role"))
      else
        role = result.value&.dig(:role) || Role.new(attributes)
        flash.now[:alert] = service_error_message(result)
        render inertia: "Admin/Roles/Form",
          props: form_props(
            role,
            selected_permission_ids:,
            form_errors: inertia_form_errors(result, prefix: "role")
          ),
          status: :unprocessable_entity
      end
    end

    def update
      attributes = role_params
      selected_permission_ids = requested_permission_ids
      result = apply_role_mutation(
        :update,
        role: @role,
        attributes:,
        permissions_submitted: permission_ids_submitted?,
        permission_ids: selected_permission_ids
      )
      if result.success?
        redirect_to admin_role_path(@role),
          notice: t("mcweb.flash.updated", resource: t("mcweb.resources.role"))
      else
        role = result.value&.dig(:role) || @role
        role.assign_attributes(attributes.except(:key))
        flash.now[:alert] = service_error_message(result)
        render inertia: "Admin/Roles/Form",
          props: form_props(
            role,
            editing: true,
            selected_permission_ids:,
            form_errors: inertia_form_errors(result, prefix: "role")
          ),
          status: :unprocessable_entity
      end
    end

    def destroy
      result = apply_role_mutation(
        :destroy,
        role: @role,
        replacement_role_id: params.dig(:role, :replacement_role_id)
      )
      if result.success?
        redirect_to admin_roles_path,
          notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.role"))
      else
        redirect_to edit_admin_role_path(@role), alert: service_error_message(result)
      end
    end

    private

    def set_role
      @role = Role.includes(:permissions).find(params[:id])
    end

    def role_params
      params.expect(role: %i[name key description])
    end

    def apply_role_mutation(operation, role: nil, attributes: {}, permission_ids: [],
                            permissions_submitted: false, replacement_role_id: nil)
      Identity::ApplyRoleMutation.call(
        actor: current_user,
        operation:,
        role:,
        attributes:,
        permission_ids:,
        permissions_submitted:,
        replacement_role_id:
      )
    end

    def requested_permission_ids
      Array(params.dig(:role, :permission_ids))
    end

    def permission_ids_submitted?
      params.fetch(:role, {}).key?(:permission_ids)
    end

    def show_props(role)
      member_count = role.user_roles.count
      {
        title: role.name,
        subtitle: role.description,
        role: serialize_role(role, member_count:),
        permissions: role.permissions.order(:key).map do |permission|
          serialize_permission(permission)
        end,
        editUrl: editable_role?(role) ? edit_admin_role_path(role) : nil,
        backUrl: admin_roles_path
      }
    end

    def form_props(role, editing: false, selected_permission_ids: nil, form_errors: {})
      selected_ids = selected_permission_ids || role.permission_ids
      member_count = role.persisted? ? role.user_roles.count : 0
      can_manage = !role.persisted? || editable_role?(role)
      {
        title: t(editing ? "mcweb.role_admin.edit_title" : "mcweb.role_admin.new_title"),
        role: serialize_role(role, member_count:, permission_ids: selected_ids),
        permissionCatalog: serialized_permission_catalog(role, selected_ids:),
        replacementRoles: replacement_roles_for(role),
        canManage: can_manage,
        submitUrl: editing ? admin_role_path(role) : admin_roles_path,
        method: editing ? "patch" : "post",
        deleteUrl: editing && can_manage ? admin_role_path(role) : nil,
        backUrl: editing ? admin_role_path(role) : admin_roles_path,
        formErrors: form_errors
      }
    end

    def serialize_role_summary(role, member_counts:)
      {
        id: role.id,
        name: role.name,
        key: role.key,
        description: role.description,
        permissionCount: role.permissions.size,
        memberCount: member_counts.fetch(role.id, 0),
        systemRole: role.system_role?,
        url: admin_role_path(role)
      }
    end

    def serialize_role(role, member_count:, permission_ids: role.permission_ids)
      {
        id: role.id,
        name: role.name.to_s,
        key: role.key.to_s,
        description: role.description.to_s,
        permissionIds: Array(permission_ids).filter_map do |id|
          Integer(id, exception: false)
        end.uniq,
        memberCount: member_count,
        systemRole: role.system_role?
      }
    end

    def serialized_permission_catalog(role, selected_ids:)
      selected_ids = Array(selected_ids).filter_map do |id|
        Integer(id, exception: false)
      end
      selected_permissions = Permission.where(id: selected_ids).index_by(&:key)
      catalog = Identity::PermissionCatalog.grouped_json(locale: I18n.locale)
      catalog_keys = catalog.flat_map { |domain| domain.fetch(:permissions).pluck(:key) }
      records = Permission.where(key: catalog_keys).index_by(&:key)
      grantable_keys = grantable_permission_keys_for_current_user

      domains = catalog.filter_map do |domain|
        permissions = domain.fetch(:permissions).filter_map do |permission|
          record = records[permission.fetch(:key)]
          next unless record

          serialize_catalog_permission(
            permission,
            record:,
            selected: selected_ids.include?(record.id),
            grantable_keys:
          )
        end
        next if permissions.empty?

        domain.merge(permissions:)
      end

      orphaned = selected_permissions.keys - catalog_keys
      if orphaned.any?
        domains << {
          key: "legacy",
          name: t("mcweb.permission_catalog.legacy_group"),
          permissions: orphaned.sort.map do |key|
            permission = selected_permissions.fetch(key)
            {
              id: permission.id,
              key:,
              name: permission.name,
              description: t("mcweb.permission_catalog.legacy_description"),
              grantable: false,
              selected: true
            }
          end
        }
      end
      domains
    end

    def serialize_catalog_permission(permission, record:, selected:, grantable_keys:)
      {
        id: record.id,
        key: permission.fetch(:key),
        name: permission.fetch(:name),
        description: permission.fetch(:description),
        grantable: grantable_keys.include?(permission.fetch(:key)),
        selected:
      }
    end

    def serialize_permission(permission)
      entry = Identity::PermissionCatalog.find(permission.key)
      {
        key: permission.key,
        name: entry ? I18n.t("#{entry.i18n_key}.name", default: permission.name) : permission.name,
        description: entry ? I18n.t(
          "#{entry.i18n_key}.description",
          default: permission.description
        ) : permission.description
      }
    end

    def replacement_roles_for(role)
      return [] unless role.persisted? && editable_role?(role)

      Role.includes(:permissions).where.not(id: role.id).order(:name).filter_map do |candidate|
        next unless manageable_role?(candidate)

        { id: candidate.id, name: candidate.name, key: candidate.key }
      end
    end

    def editable_role?(role)
      can_manage_roles? && !role.system_role? && manageable_role?(role)
    end

    def manageable_role?(role)
      return true if current_user.account_owner?

      keys = role.permissions.map(&:key)
      (keys - grantable_permission_keys_for_current_user).empty?
    end

    def grantable_permission_keys_for_current_user
      @grantable_permission_keys_for_current_user ||= begin
        assignable = Identity::PermissionCatalog.assignable_keys
        if current_user.account_owner?
          assignable
        else
          assignable & Identity::AccountAccess.effective_permission_keys(current_user)
        end
      end
    end

    def can_manage_roles?
      @can_manage_roles ||= begin
        result = Identity::PermissionChecker.call(
          user: current_user,
          permission_key: "identity.roles.manage"
        )
        result.success? && result.value[:allowed]
      end
    end
  end
end
