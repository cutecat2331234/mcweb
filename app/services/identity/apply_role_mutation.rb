# frozen_string_literal: true

require "set"

module Identity
  class ApplyRoleMutation < ApplicationService
    OPERATIONS = %i[create update destroy].freeze
    MANAGE_PERMISSION = "identity.roles.manage"
    ROLE_ATTRIBUTES = %i[name key description].freeze
    AUDIT_ACTIONS = {
      create: "identity.role.created",
      update: "identity.role.updated",
      destroy: "identity.role.deleted"
    }.freeze

    def initialize(actor:, operation:, role: nil, attributes: {},
                   permission_ids: [], permissions_submitted: false,
                   replacement_role_id: nil,
                   assignable_permission_keys: PermissionCatalog.assignable_keys)
      @actor = actor
      @operation = operation.to_s.to_sym
      @role = role
      @attributes = attributes.to_h.deep_symbolize_keys.slice(*ROLE_ATTRIBUTES)
      @permission_ids = Array(permission_ids)
      @permissions_submitted = permissions_submitted
      @replacement_role_id = replacement_role_id
      @assignable_permission_keys = Array(assignable_permission_keys).map(&:to_s).to_set.freeze
    end

    def call
      return failure("Unknown role operation.", code: "invalid_operation") unless OPERATIONS.include?(@operation)

      ActiveRecord::Base.transaction do
        PermissionMutationLock.acquire_exclusive!
        @actor = User.uncached { User.find_by(id: @actor&.id) }

        if operation_allowed?
          send(:"apply_#{@operation}")
        else
          failure("Not allowed.", code: "forbidden")
        end
      end
    rescue ActiveRecord::RecordInvalid => error
      failure(
        error.record.errors.full_messages.to_sentence,
        code: "validation_failed",
        errors: error.record.errors.to_hash,
        role: error.record.is_a?(Role) ? error.record : @role
      )
    rescue ActiveRecord::RecordNotFound
      failure("Role not found.", code: "not_found")
    end

    private

    def operation_allowed?
      @actor&.session_eligible? && permission_allowed?(MANAGE_PERMISSION)
    end

    def apply_create
      role = Role.new(@attributes)
      permissions = resolve_requested_permissions(current_keys: [])
      return permissions if permissions.is_a?(ServiceResult)

      role.save!
      role.permissions = permissions
      audit!(role:, before_state: { exists: false }, after_state: role_snapshot(role))
      success(role:)
    end

    def apply_update
      role = locked_role
      return failure("System roles cannot be changed.", code: "system_role_immutable", role:) if role.system_role?
      return failure("Not allowed.", code: "forbidden_role", role:) unless role_manageable?(role)

      permissions =
        if @permissions_submitted
          resolve_requested_permissions(current_keys: role.permissions.pluck(:key))
        else
          role.permissions.to_a
        end
      return permissions if permissions.is_a?(ServiceResult)

      before_state = role_snapshot(role)
      role.update!(@attributes.except(:key))
      role.permissions = permissions if @permissions_submitted
      audit!(role:, before_state:, after_state: role_snapshot(role))
      success(role:)
    end

    def apply_destroy
      roles = locked_retirement_roles
      return roles if roles.is_a?(ServiceResult)

      role = roles.fetch(:role)
      replacement_role = roles[:replacement_role]
      return failure("System roles cannot be deleted.", code: "system_role_immutable", role:) if role.system_role?
      return failure("Not allowed.", code: "forbidden_role", role:) unless role_manageable?(role)
      if replacement_role && !role_manageable?(replacement_role)
        return failure("forbidden_replacement_role", code: "forbidden_replacement_role", role:)
      end

      assignments = UserRole.lock.where(role_id: role.id).order(:id).to_a
      if assignments.any? && replacement_role.nil?
        return failure(
          "A replacement role is required before retiring an assigned role.",
          code: "replacement_role_required",
          role:
        )
      end

      before_state = role_snapshot(role)
      reassigned_count = 0
      already_assigned_count = 0
      if replacement_role
        existing_user_ids = UserRole.lock
          .where(role_id: replacement_role.id, user_id: assignments.map(&:user_id))
          .pluck(:user_id)
          .to_set
        assignments.each do |assignment|
          if existing_user_ids.include?(assignment.user_id)
            already_assigned_count += 1
          else
            UserRole.create!(user_id: assignment.user_id, role_id: replacement_role.id)
            reassigned_count += 1
          end
          assignment.destroy!
        end
      end
      role.destroy!
      audit!(
        role:,
        before_state:,
        after_state: { exists: false },
        metadata: {
          replacement_role_id: replacement_role&.id,
          assignment_count: assignments.size,
          reassigned_count:,
          already_assigned_count:
        }
      )
      success(
        role:,
        replacement_role:,
        assignment_count: assignments.size,
        reassigned_count:,
        already_assigned_count:
      )
    end

    def locked_retirement_roles
      source_id = @role.respond_to?(:id) ? @role.id : @role
      source_id = Integer(source_id, exception: false)
      return failure("Role not found.", code: "not_found") unless source_id

      replacement_id = normalized_replacement_role_id
      return replacement_id if replacement_id.is_a?(ServiceResult)
      if replacement_id == source_id
        return failure(
          "A role cannot replace itself.",
          code: "replacement_role_same",
          role: @role
        )
      end

      ids = [ source_id, replacement_id ].compact.sort
      roles = Role.lock.where(id: ids).order(:id).index_by(&:id)
      role = roles[source_id]
      return failure("Role not found.", code: "not_found") unless role

      replacement_role = replacement_id ? roles[replacement_id] : nil
      if replacement_id && replacement_role.nil?
        return failure(
          "Replacement role not found.",
          code: "replacement_role_not_found",
          role:
        )
      end

      { role:, replacement_role: }
    end

    def normalized_replacement_role_id
      return if @replacement_role_id.blank?

      value = Integer(@replacement_role_id, exception: false)
      return value if value&.positive?

      failure("Replacement role not found.", code: "replacement_role_not_found", role: @role)
    end

    def locked_role
      id = @role.respond_to?(:id) ? @role.id : @role
      Role.lock.find(id)
    end

    def resolve_requested_permissions(current_keys:)
      normalized_ids = normalize_permission_ids
      return normalized_ids if normalized_ids.is_a?(ServiceResult)

      permissions = Permission.where(id: normalized_ids).order(:key).to_a
      if permissions.size != normalized_ids.size
        return failure("Invalid permission ids.", code: "invalid_permissions", role: @role)
      end

      current = Array(current_keys).map(&:to_s).to_set
      requested = permissions.map(&:key).to_set
      newly_granted = requested - current
      unknown_keys = newly_granted - @assignable_permission_keys
      if unknown_keys.any?
        return failure(
          "Invalid permission keys.",
          code: "invalid_permissions",
          value: { invalid_permission_keys: unknown_keys.to_a.sort, role: @role }
        )
      end
      return permissions if @actor.account_owner?

      forbidden_keys = newly_granted - actor_permission_keys
      return permissions if forbidden_keys.empty?

      failure(
        "Not allowed.",
        code: "forbidden_permissions",
        value: { forbidden_permission_keys: forbidden_keys.to_a.sort, role: @role }
      )
    end

    def normalize_permission_ids
      normalized = @permission_ids.reject(&:blank?).filter_map do |value|
        Integer(value, exception: false)
      end
      return normalized.uniq.sort if normalized.size == @permission_ids.reject(&:blank?).size

      failure("Invalid permission ids.", code: "invalid_permissions", role: @role)
    end

    def role_manageable?(role)
      return true if @actor.account_owner?

      keys = role.permissions.pluck(:key).to_set
      keys.subset?(@assignable_permission_keys) && keys.subset?(actor_permission_keys)
    end

    def actor_permission_keys
      @actor_permission_keys ||= Identity::AccountAccess
        .effective_permission_keys(@actor)
        .to_set
    end

    def permission_allowed?(permission_key)
      result = Identity::PermissionChecker.call(
        user: @actor,
        permission_key:
      )
      result.success? && result.value[:allowed]
    end

    def audit!(role:, before_state:, after_state:, metadata: {})
      Administration::AuditLogger.call(
        actor: @actor,
        action: AUDIT_ACTIONS.fetch(@operation),
        resource: role,
        metadata: { operation: @operation.to_s }.merge(metadata),
        before_state:,
        after_state:
      )
    end

    def role_snapshot(role)
      {
        role_id: role.id,
        key: role.key,
        name: role.name,
        permission_keys: role.permissions.order(:key).pluck(:key)
      }
    end

    def success(**value)
      ServiceResult.success(value.merge(operation: @operation))
    end

    def failure(error, code:, errors: nil, role: nil, value: nil)
      payload = value || {}
      payload[:role] ||= role if role
      ServiceResult.failure(
        error:,
        code:,
        errors:,
        value: payload.presence
      )
    end
  end
end
