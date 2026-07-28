# frozen_string_literal: true

require "test_helper"

class Identity::ApplyRoleMutationTest < ActiveSupport::TestCase
  setup do
    @manager = create_user
    grant_permission(@manager, "identity.roles.manage")
  end

  test "non owners cannot add permissions they do not hold" do
    delegated_permission = permission_for("forum.topics.lock")

    result = mutate(
      actor: @manager,
      operation: :create,
      attributes: {
        name: "Escalated role",
        key: "escalated_role_#{SecureRandom.hex(4)}"
      },
      permission_ids: [ delegated_permission.id ],
      permissions_submitted: true
    )

    assert result.failure?
    assert_equal "forbidden_permissions", result.code
    assert_equal [ delegated_permission.key ], result.value[:forbidden_permission_keys]
    assert_not Role.exists?(name: "Escalated role")
  end

  test "non owners cannot update or delete roles containing permissions they do not hold" do
    protected_permission = permission_for("system.settings.manage")
    protected_role = create_role_with_permissions(
      name: "Protected role",
      permissions: [ protected_permission ]
    )

    updated = mutate(
      actor: @manager,
      operation: :update,
      role: protected_role,
      attributes: { name: "Escalated edit" },
      permissions_submitted: false
    )
    destroyed = mutate(
      actor: @manager,
      operation: :destroy,
      role: protected_role
    )

    assert updated.failure?
    assert_equal "forbidden_role", updated.code
    assert destroyed.failure?
    assert_equal "forbidden_role", destroyed.code
    assert_equal "Protected role", protected_role.reload.name
    assert Role.exists?(protected_role.id)
  end

  test "non owners can delegate an active catalog permission they hold" do
    delegated_permission = permission_for("forum.topics.lock")
    assert Identity::PermissionCatalog.active_key?(delegated_permission.key)
    grant_permission(@manager, delegated_permission.key)

    result = mutate(
      actor: @manager.reload,
      operation: :create,
      attributes: {
        name: "Topic moderators",
        key: "topic_moderators_#{SecureRandom.hex(4)}"
      },
      permission_ids: [ delegated_permission.id ],
      permissions_submitted: true
    )

    assert result.success?
    role = result.value.fetch(:role)
    assert_equal [ delegated_permission.key ], role.permissions.pluck(:key)
    assert AuditLog.exists?(
      action: "identity.role.created",
      resource_type: "Role",
      resource_id: role.id
    )
  end

  test "permissions outside the active catalog cannot be delegated even when the actor holds them" do
    retired_permission = permission_for("retired.plugin.permission")
    refute Identity::PermissionCatalog.active_key?(retired_permission.key)
    grant_permission(@manager, retired_permission.key)

    result = mutate(
      actor: @manager.reload,
      operation: :create,
      attributes: {
        name: "Retired permission role",
        key: "retired_permission_role_#{SecureRandom.hex(4)}"
      },
      permission_ids: [ retired_permission.id ],
      permissions_submitted: true
    )

    assert result.failure?
    assert_equal "invalid_permissions", result.code
    assert_equal [ retired_permission.key ], result.value[:invalid_permission_keys]
    assert_not Role.exists?(name: "Retired permission role")
  end

  test "system roles cannot be updated or deleted" do
    system_role = Role.create!(
      name: "Immutable system role",
      key: "immutable_system_role_#{SecureRandom.hex(4)}",
      system_role: true
    )
    owner = create_user(account_type: "owner")

    updated = mutate(
      actor: owner,
      operation: :update,
      role: system_role,
      attributes: { name: "Changed system role" },
      permissions_submitted: false
    )
    destroyed = mutate(
      actor: owner,
      operation: :destroy,
      role: system_role
    )

    assert updated.failure?
    assert_equal "system_role_immutable", updated.code
    assert destroyed.failure?
    assert_equal "system_role_immutable", destroyed.code
    assert_equal "Immutable system role", system_role.reload.name
    assert Role.exists?(system_role.id)
  end

  test "omitting permission ids preserves the existing role grants" do
    existing_permission = permission_for("forum.topics.lock")
    grant_permission(@manager, existing_permission.key)
    role = create_role_with_permissions(
      name: "Existing moderator",
      permissions: [ existing_permission ]
    )

    result = mutate(
      actor: @manager.reload,
      operation: :update,
      role: role,
      attributes: { name: "Renamed moderator" },
      permissions_submitted: false
    )

    assert result.success?
    assert_equal "Renamed moderator", role.reload.name
    assert_equal [ existing_permission.key ], role.permissions.pluck(:key)
  end

  private

  def mutate(**arguments)
    Identity::ApplyRoleMutation.call(**arguments)
  end

  def permission_for(key)
    Permission.find_or_create_by!(key:) do |permission|
      permission.name = key
      permission.category = key.split(".").first
    end
  end

  def create_role_with_permissions(name:, permissions:)
    Role.create!(
      name:,
      key: "#{name.parameterize(separator: '_')}_#{SecureRandom.hex(4)}",
      permissions:
    )
  end
end
