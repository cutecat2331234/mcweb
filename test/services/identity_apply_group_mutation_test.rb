# frozen_string_literal: true

require "test_helper"

class Identity::ApplyGroupMutationTest < ActiveSupport::TestCase
  ACTIVE_PERMISSION_KEYS = %w[
    forum.sections.manage
    forum.topics.lock
    identity.groups.manage
    identity.groups.members.assign
    identity.groups.permissions.manage
    identity.groups.read
  ].freeze

  setup do
    @actor = create_user
    grant_permission(@actor, "identity.groups.manage")
    grant_permission(@actor, "identity.groups.members.assign")
    grant_permission(@actor, "identity.groups.permissions.manage")
    grant_permission(@actor, "forum.topics.lock")
    @member = create_user
  end

  test "group mutations are authorized separately from permission delegation" do
    manager = create_user
    grant_permission(manager, "identity.groups.manage")

    denied = mutate(
      actor: manager,
      operation: :create,
      attributes: {
        name: "Denied permissions",
        priority: 1,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert denied.failure?
    assert_equal "forbidden", denied.code
    assert_nil Community::UserGroup.find_by(name: "Denied permissions")

    grant_permission(manager, "identity.groups.permissions.manage")
    still_denied = mutate(
      actor: manager.reload,
      operation: :create,
      attributes: {
        name: "Undelegable permissions",
        priority: 1,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert still_denied.failure?
    assert_equal "forbidden_permissions", still_denied.code

    grant_permission(manager, "forum.topics.lock")
    allowed = mutate(
      actor: manager.reload,
      operation: :create,
      attributes: {
        name: "Delegated permissions",
        priority: 1,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert allowed.success?
    assert_equal [ "forum.topics.lock" ], allowed.value[:group].permission_keys
  end

  test "group managers can edit details without changing grants they cannot manage" do
    group = create_group(name: "Existing grants", priority: 1)
    group.update!(permissions: [ "forum.topics.lock" ])
    manager = create_user
    grant_permission(manager, "identity.groups.manage")

    allowed = mutate(
      actor: manager,
      operation: :update,
      group: group,
      attributes: {
        name: "Renamed group",
        priority: 2,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert allowed.success?
    assert_equal "Renamed group", group.reload.name

    denied = mutate(
      actor: manager.reload,
      operation: :update,
      group: group,
      attributes: {
        name: "Escalated group",
        priority: 2,
        permissions: [ "forum.sections.manage", "forum.topics.lock" ]
      }
    )
    assert denied.failure?
    assert_equal "forbidden", denied.code
    assert_equal "Renamed group", group.reload.name
    assert_equal [ "forum.topics.lock" ], group.permission_keys
  end

  test "group managers can create an empty group without permission delegation" do
    manager = create_user
    grant_permission(manager, "identity.groups.manage")

    result = mutate(
      actor: manager,
      operation: :create,
      attributes: {
        name: "Empty group",
        priority: 1,
        permissions: []
      }
    )

    assert result.success?
    assert_empty result.value[:group].permission_keys
  end

  test "unknown and inactive permission keys are rejected before persistence" do
    result = mutate(
      actor: @actor,
      operation: :create,
      attributes: {
        name: "Unknown permissions",
        priority: 1,
        permissions: [ "forum.not_in_catalog" ]
      }
    )

    assert result.failure?
    assert_equal "invalid_permissions", result.code
    assert_equal [ "forum.not_in_catalog" ], result.value[:invalid_permission_keys]
    assert_nil Community::UserGroup.find_by(name: "Unknown permissions")
    assert_empty AuditLog.where(action: "identity.group.created")
  end

  test "unchanged legacy grants do not block unrelated group edits" do
    group = create_group(name: "Legacy group", priority: 1)
    group.update!(permissions: [ "legacy.permission" ])

    result = mutate(
      actor: @actor,
      operation: :update,
      group: group,
      attributes: {
        name: "Legacy group renamed",
        priority: 2,
        permissions: [ "legacy.permission" ]
      }
    )

    assert result.success?
    assert_equal "Legacy group renamed", group.reload.name
    assert_equal [ "legacy.permission" ], group.permission_keys
  end

  test "create and update persist a sanitized audit snapshot in the same transaction" do
    created = mutate(
      actor: @actor,
      operation: :create,
      attributes: {
        name: "Moderators",
        banner_text: "Public badge",
        color_hex: "#123456",
        priority: 10,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert created.success?
    group = created.value[:group]

    updated = mutate(
      actor: @actor,
      operation: :update,
      group: group,
      attributes: {
        name: "Senior moderators",
        priority: 20,
        permissions: [ "forum.topics.lock" ]
      }
    )
    assert updated.success?

    create_audit = AuditLog.find_by!(action: "identity.group.created", resource_id: group.id)
    update_audit = AuditLog.find_by!(action: "identity.group.updated", resource_id: group.id)
    assert_equal false, create_audit.before_state.fetch("exists")
    assert_equal "Moderators", create_audit.after_state.fetch("name")
    assert_equal "Moderators", update_audit.before_state.fetch("name")
    assert_equal "Senior moderators", update_audit.after_state.fetch("name")

    serialized = [
      create_audit.metadata,
      create_audit.before_state,
      create_audit.after_state,
      update_audit.metadata,
      update_audit.before_state,
      update_audit.after_state
    ].to_json
    assert_not_includes serialized, @actor.email
    assert_not_includes serialized, @actor.password_digest
    assert_not_includes serialized, "Public badge"
    assert_not_includes serialized, "#123456"
  end

  test "audit failure rolls the model mutation back" do
    assert_raises(RuntimeError) do
      with_active_permission_catalog do
        Administration::AuditLogger.stub(:call, ->(**) { raise "audit unavailable" }) do
          Identity::ApplyGroupMutation.call(
            actor: @actor,
            operation: :create,
            attributes: {
              name: "Must roll back",
              priority: 1,
              permissions: [ "forum.topics.lock" ]
            }
          )
        end
      end
    end

    assert_nil Community::UserGroup.find_by(name: "Must roll back")
  end

  test "membership mutations maintain exactly one primary while memberships remain" do
    lower = create_group(name: "Lower", priority: 10)
    higher = create_group(name: "Higher", priority: 20)

    first = mutate(
      actor: @actor,
      operation: :add_member,
      group: lower,
      user: @member
    )
    assert first.success?
    assert Community::GroupMembership.find_by!(user: @member, user_group: lower).is_primary?

    second = mutate(
      actor: @actor,
      operation: :add_member,
      group: higher,
      user: @member
    )
    assert second.success?
    assert_equal 1, @member.group_memberships.primary.count
    assert Community::GroupMembership.find_by!(user: @member, user_group: lower).is_primary?

    promoted = mutate(
      actor: @actor,
      operation: :set_primary,
      group: higher,
      user: @member
    )
    assert promoted.success?
    assert_equal higher.id, primary_group_id(@member)

    removed = mutate(
      actor: @actor,
      operation: :remove_member,
      group: higher,
      user: @member
    )
    assert removed.success?
    assert_equal lower.id, primary_group_id(@member)
    assert_equal 1, @member.group_memberships.primary.count

    audit = AuditLog.find_by!(action: "identity.group.member_removed", resource_id: higher.id)
    serialized = [ audit.metadata, audit.before_state, audit.after_state ].to_json
    assert_not_includes serialized, @member.email
    assert_equal lower.id, audit.after_state.fetch("primary_group_id")
  end

  test "primary repair locks membership rows without locking every joined group" do
    group = create_group(name: "Scoped locking", priority: 10)
    sql_statements = []
    subscriber = lambda do |_name, _started, _finished, _unique_id, payload|
      sql_statements << payload[:sql].to_s
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      result = mutate(
        actor: @actor,
        operation: :add_member,
        group: group,
        user: @member
      )
      assert result.success?
    end

    lock_sql = sql_statements.find do |sql|
      sql.include?("FOR UPDATE OF community_group_memberships")
    end
    assert lock_sql, "primary repair must scope its lock to membership rows"
    refute_match(/FOR UPDATE OF community_user_groups/, lock_sql)
  end

  test "membership managers cannot delegate a group permission they do not hold" do
    privileged_group = create_group(name: "Privileged", priority: 100)
    privileged_group.update!(permissions: [ "forum.sections.manage" ])

    result = mutate(
      actor: @actor,
      operation: :add_member,
      group: privileged_group,
      user: @actor
    )

    assert result.failure?
    assert_equal "forbidden_permissions", result.code
    assert_not Community::GroupMembership.exists?(user: @actor, user_group: privileged_group)
  end

  test "existing high permissions can be retained or removed but cannot be added back" do
    privileged_group = create_group(name: "Existing high grants", priority: 100)
    privileged_group.update!(permissions: [ "forum.sections.manage" ])

    retained = mutate(
      actor: @actor,
      operation: :update,
      group: privileged_group,
      attributes: {
        name: "Existing high grants renamed",
        priority: 101,
        permissions: [ "forum.sections.manage" ]
      }
    )
    assert retained.success?

    removed = mutate(
      actor: @actor,
      operation: :update,
      group: privileged_group,
      attributes: {
        name: privileged_group.reload.name,
        priority: privileged_group.priority,
        permissions: []
      }
    )
    assert removed.success?
    assert_empty privileged_group.reload.permission_keys

    restored = mutate(
      actor: @actor,
      operation: :update,
      group: privileged_group,
      attributes: {
        name: privileged_group.name,
        priority: privileged_group.priority,
        permissions: [ "forum.sections.manage" ]
      }
    )
    assert restored.failure?
    assert_equal "forbidden_permissions", restored.code
    assert_empty privileged_group.reload.permission_keys
  end

  test "owners cannot delegate permissions outside the assignable catalog" do
    owner = create_user(account_type: "owner")
    legacy_group = create_group(name: "Legacy owner group", priority: 100)
    legacy_group.update!(permissions: [ "retired.plugin.permission" ])

    result = mutate(
      actor: owner,
      operation: :add_member,
      group: legacy_group,
      user: @member
    )

    assert result.failure?
    assert_equal "forbidden_permissions", result.code
    assert_not Community::GroupMembership.exists?(user: @member, user_group: legacy_group)
  end

  test "changing the default membership policy requires membership delegation" do
    manager = create_user
    grant_permission(manager, "identity.groups.manage")
    grant_permission(manager, "identity.groups.permissions.manage")
    grant_permission(manager, "forum.topics.lock")

    result = mutate(
      actor: manager,
      operation: :create,
      attributes: {
        name: "Unsafe default",
        priority: 1,
        is_primary_default: true,
        permissions: [ "forum.topics.lock" ]
      }
    )

    assert result.failure?
    assert_equal "forbidden", result.code
    assert_nil Community::UserGroup.find_by(name: "Unsafe default")
  end

  test "membership managers can disable a dangerous default without holding its grants" do
    group = create_group(name: "Dangerous default", priority: 1)
    group.update!(
      is_primary_default: true,
      permissions: [ "forum.sections.manage" ]
    )

    result = mutate(
      actor: @actor,
      operation: :update,
      group: group,
      attributes: {
        name: group.name,
        priority: group.priority,
        is_primary_default: false,
        permissions: group.permission_keys
      }
    )

    assert result.success?
    assert_not group.reload.is_primary_default?
  end

  test "Chinese validation errors use the identity group attribute translations" do
    result = I18n.with_locale(:"zh-CN") do
      mutate(
        actor: @actor,
        operation: :create,
        attributes: {
          name: "",
          priority: 1,
          permissions: []
        }
      )
    end

    assert result.failure?
    assert_includes result.error, "名称"
    assert_not_includes result.error, "Name"
  end

  test "destroying a primary group promotes the highest-priority remaining group" do
    lower = create_group(name: "Lower destroy", priority: 10)
    higher = create_group(name: "Higher destroy", priority: 20)
    Community::GroupMembership.create!(user: @member, user_group: lower, is_primary: false)
    Community::GroupMembership.create!(user: @member, user_group: higher, is_primary: true)

    result = mutate(
      actor: @actor,
      operation: :destroy,
      group: higher
    )

    assert result.success?
    assert_not Community::UserGroup.exists?(higher.id)
    assert_equal lower.id, primary_group_id(@member)
    assert AuditLog.exists?(action: "identity.group.deleted", resource_id: higher.id)
  end

  private

  def mutate(**arguments)
    with_active_permission_catalog do
      Identity::ApplyGroupMutation.call(**arguments)
    end
  end

  def with_active_permission_catalog(&block)
    Identity::PermissionCatalog.stub(:assignable_keys, ACTIVE_PERMISSION_KEYS, &block)
  end

  def create_group(name:, priority:)
    Community::UserGroup.create!(
      name: name,
      priority: priority,
      permissions: []
    )
  end

  def primary_group_id(user)
    Community::GroupMembership
      .where(user: user, is_primary: true)
      .pick(:community_user_group_id)
  end
end
