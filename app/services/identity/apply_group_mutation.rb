# frozen_string_literal: true

module Identity
  class ApplyGroupMutation < ApplicationService
    OPERATIONS = %i[
      create
      update
      destroy
      add_member
      remove_member
      set_primary
    ].freeze
    GROUP_OPERATIONS = %i[create update destroy].freeze
    MEMBERSHIP_OPERATIONS = %i[add_member remove_member set_primary].freeze
    GROUP_ATTRIBUTES = %i[
      name
      color_hex
      priority
      banner_text
      is_primary_default
      permissions
    ].freeze

    GROUP_MANAGE_PERMISSION = "identity.groups.manage"
    MEMBERSHIP_MANAGE_PERMISSION = "identity.groups.members.assign"
    PERMISSIONS_MANAGE_PERMISSION = "identity.groups.permissions.manage"

    AUDIT_ACTIONS = {
      create: "identity.group.created",
      update: "identity.group.updated",
      destroy: "identity.group.deleted",
      add_member: "identity.group.member_added",
      remove_member: "identity.group.member_removed",
      set_primary: "identity.group.primary_changed"
    }.freeze

    def initialize(actor:, operation:, group: nil, user: nil, attributes: {},
                   assignable_permission_keys: Identity::PermissionCatalog.assignable_keys)
      @actor = actor
      @operation = operation.to_s.to_sym
      @group = group
      @user = user
      @attributes = normalize_attributes(attributes)
      @assignable_permission_keys = Array(assignable_permission_keys).map(&:to_s).uniq.freeze
    end

    def call
      return failure("Unknown group operation.", code: "invalid_operation") unless OPERATIONS.include?(@operation)
      return failure("Not allowed.", code: "forbidden") unless operation_allowed?

      result = nil
      ActiveRecord::Base.transaction do
        result = send(:"apply_#{@operation}")
      end
      result
    rescue ActiveRecord::RecordInvalid => error
      failure(
        error.record.errors.full_messages.to_sentence,
        code: "validation_failed",
        errors: error.record.errors.to_hash,
        group: error.record.is_a?(Community::UserGroup) ? error.record : @group
      )
    rescue ActiveRecord::RecordNotDestroyed => error
      failure(
        error.record.errors.full_messages.to_sentence,
        code: "validation_failed",
        errors: error.record.errors.to_hash,
        group: error.record
      )
    rescue ActiveRecord::RecordNotFound
      failure("User group or member not found.", code: "not_found")
    end

    private

    def operation_allowed?
      return false unless @actor&.session_eligible?

      required_permission =
        if GROUP_OPERATIONS.include?(@operation)
          GROUP_MANAGE_PERMISSION
        else
          MEMBERSHIP_MANAGE_PERMISSION
        end
      permission_allowed?(required_permission)
    end

    def validate_permission_mutation(current_keys:)
      return unless permissions_submitted?
      normalized_current_keys = Array(current_keys).map(&:to_s).uniq.sort
      return if submitted_permission_keys == normalized_current_keys

      newly_submitted_keys = submitted_permission_keys - normalized_current_keys
      unknown_keys = newly_submitted_keys - @assignable_permission_keys
      if unknown_keys.any?
        return failure(
          "Invalid permission keys.",
          code: "invalid_permissions",
          value: { invalid_permission_keys: unknown_keys, group: @group }
        )
      end
      return failure("Not allowed.", code: "forbidden") unless permission_allowed?(PERMISSIONS_MANAGE_PERMISSION)

      return if @actor.account_owner?

      granted_keys = newly_submitted_keys
      forbidden_keys = granted_keys.reject { |key| permission_allowed?(key) }
      return if forbidden_keys.empty?

      failure(
        "Not allowed.",
        code: "forbidden_permissions",
        value: { forbidden_permission_keys: forbidden_keys, group: @group }
      )
    end

    def apply_create
      permission_error = validate_permission_mutation(current_keys: [])
      return permission_error if permission_error

      primary_policy_error = validate_primary_default_change(
        previous_value: false,
        next_value: @attributes[:is_primary_default],
        permission_keys: submitted_permission_keys
      )
      return primary_policy_error if primary_policy_error

      group = Community::UserGroup.new(@attributes)
      before_state = { exists: false }
      group.save!
      audit!(
        group: group,
        before_state: before_state,
        after_state: group_snapshot(group)
      )
      success(group: group)
    end

    def apply_update
      group = locked_group
      permission_error = validate_permission_mutation(current_keys: group.permission_keys)
      return permission_error if permission_error

      primary_policy_error = validate_primary_default_change(
        previous_value: group.is_primary_default?,
        next_value: @attributes.fetch(:is_primary_default, group.is_primary_default?),
        permission_keys: @attributes.fetch(:permissions, group.permission_keys)
      )
      return primary_policy_error if primary_policy_error

      before_state = group_snapshot(group)
      group.update!(@attributes)
      audit!(
        group: group,
        before_state: before_state,
        after_state: group_snapshot(group)
      )
      success(group: group)
    end

    def apply_destroy
      group = locked_group
      if group.group_memberships.exists? && !permission_allowed?(MEMBERSHIP_MANAGE_PERMISSION)
        return failure("Not allowed.", code: "forbidden")
      end
      if group.permission_keys.any? && !permission_allowed?(PERMISSIONS_MANAGE_PERMISSION)
        return failure("Not allowed.", code: "forbidden")
      end

      before_state = group_snapshot(group)
      affected_users = lock_group_members(group)
      group.destroy!
      affected_users.each { |user| ensure_primary_membership!(user) }
      audit!(
        group: group,
        before_state: before_state,
        after_state: { exists: false }
      )
      success(group: group)
    end

    def apply_add_member
      group = locked_group
      unless permission_keys_delegable?(group.permission_keys)
        return failure("Not allowed.", code: "forbidden_permissions")
      end

      user = locked_user
      before_state = membership_state(group: group, user: user)
      membership = Community::GroupMembership.find_or_initialize_by(
        user: user,
        user_group: group
      )
      membership.save! if membership.new_record?
      ensure_primary_membership!(user)
      membership.reload
      audit!(
        group: group,
        user: user,
        before_state: before_state,
        after_state: membership_state(group: group, user: user)
      )
      success(group: group, membership: membership, user: user)
    end

    def apply_remove_member
      group = locked_group
      user = locked_user
      membership = Community::GroupMembership.lock.find_by!(
        user: user,
        user_group: group
      )
      before_state = membership_state(group: group, user: user)
      membership.destroy!
      ensure_primary_membership!(user)
      audit!(
        group: group,
        user: user,
        before_state: before_state,
        after_state: membership_state(group: group, user: user)
      )
      success(group: group, user: user)
    end

    def apply_set_primary
      group = locked_group
      user = locked_user
      membership = Community::GroupMembership.lock.find_by!(
        user: user,
        user_group: group
      )
      before_state = primary_state(user)
      now = Time.current
      Community::GroupMembership
        .where(user: user, is_primary: true)
        .where.not(id: membership.id)
        .update_all(is_primary: false, updated_at: now)
      membership.update!(is_primary: true, updated_at: now) unless membership.is_primary?
      audit!(
        group: group,
        user: user,
        before_state: before_state,
        after_state: primary_state(user)
      )
      success(group: group, membership: membership.reload, user: user)
    end

    def locked_group
      id = @group.respond_to?(:id) ? @group.id : @group
      Community::UserGroup.lock.find(id)
    end

    def locked_user
      id = @user.respond_to?(:id) ? @user.id : @user
      User.lock.find(id)
    end

    def lock_group_members(group)
      user_ids = Community::GroupMembership
        .where(user_group: group)
        .order(:user_id)
        .pluck(:user_id)
      User.where(id: user_ids).order(:id).lock.to_a
    end

    def ensure_primary_membership!(user)
      memberships = Community::GroupMembership
        .joins(:user_group)
        .where(user: user)
        .select("community_group_memberships.*")
        .order(
          Arel.sql(
            "community_user_groups.priority DESC, " \
            "community_user_groups.name ASC, " \
            "community_group_memberships.id ASC"
          )
        )
        .lock("FOR UPDATE OF community_group_memberships")
        .to_a
      return if memberships.empty?

      keeper = memberships.find(&:is_primary?) || memberships.first
      duplicate_ids = memberships.filter_map do |membership|
        membership.id if membership.is_primary? && membership.id != keeper.id
      end
      if duplicate_ids.any?
        Community::GroupMembership
          .where(id: duplicate_ids)
          .update_all(is_primary: false, updated_at: Time.current)
      end
      keeper.update!(is_primary: true) unless keeper.is_primary?
    end

    def permissions_submitted?
      @attributes.key?(:permissions)
    end

    def permission_allowed?(permission_key)
      result = Identity::PermissionChecker.call(
        user: @actor,
        permission_key: permission_key
      )
      result.success? && result.value[:allowed]
    end

    def validate_primary_default_change(previous_value:, next_value:, permission_keys:)
      previous_enabled = ActiveModel::Type::Boolean.new.cast(previous_value) == true
      next_enabled = ActiveModel::Type::Boolean.new.cast(next_value) == true
      return if previous_enabled == next_enabled
      return failure("Not allowed.", code: "forbidden") unless permission_allowed?(MEMBERSHIP_MANAGE_PERMISSION)
      return unless next_enabled
      return if permission_keys_delegable?(permission_keys)

      failure("Not allowed.", code: "forbidden_permissions")
    end

    def permission_keys_delegable?(permission_keys)
      normalized_keys = Array(permission_keys).map(&:to_s).uniq
      return false unless (normalized_keys - @assignable_permission_keys).empty?
      return true if @actor.account_owner?

      normalized_keys.all? { |key| permission_allowed?(key) }
    end

    def submitted_permission_keys
      Array(@attributes[:permissions]).map(&:to_s)
    end

    def normalize_attributes(attributes)
      values = attributes.to_h.deep_symbolize_keys.slice(*GROUP_ATTRIBUTES)
      if values.key?(:permissions)
        values[:permissions] = normalize_permission_keys(values[:permissions])
      end
      values
    end

    def normalize_permission_keys(value)
      entries = value.is_a?(String) ? value.split(/[\s,]+/) : Array(value)
      entries.map { |key| key.to_s.strip }.reject(&:blank?).uniq.sort
    end

    def audit!(group:, before_state:, after_state:, user: nil)
      metadata = { operation: @operation.to_s }
      metadata[:target_user_public_id] = user.public_id if user
      Administration::AuditLogger.call(
        actor: @actor,
        action: AUDIT_ACTIONS.fetch(@operation),
        resource: group,
        metadata: metadata,
        before_state: before_state,
        after_state: after_state
      )
    end

    def group_snapshot(group)
      {
        group_id: group.id,
        name: group.name,
        priority: group.priority,
        is_primary_default: group.is_primary_default?,
        permission_keys: group.permission_keys.sort
      }
    end

    def membership_state(group:, user:)
      membership = Community::GroupMembership.find_by(user: user, user_group: group)
      {
        group_id: group.id,
        target_user_public_id: user.public_id,
        member: membership.present?,
        primary: membership&.is_primary? || false,
        primary_group_id: primary_group_id(user)
      }
    end

    def primary_state(user)
      {
        target_user_public_id: user.public_id,
        primary_group_id: primary_group_id(user)
      }
    end

    def primary_group_id(user)
      Community::GroupMembership
        .where(user: user, is_primary: true)
        .pick(:community_user_group_id)
    end

    def success(**value)
      ServiceResult.success(value.merge(operation: @operation))
    end

    def failure(error, code:, errors: nil, group: nil, value: nil)
      payload = value || {}
      payload[:group] ||= group if group
      ServiceResult.failure(
        error: error,
        code: code,
        errors: errors,
        value: payload.presence
      )
    end
  end
end
