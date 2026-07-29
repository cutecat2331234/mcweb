# frozen_string_literal: true

require "test_helper"
require "mcweb/plugins/registry"

class Mcweb::PluginApi::V1::IdentityTest < ActiveSupport::TestCase
  setup do
    @user = create_user(display_name: "Visible Member")
    @api = Mcweb::PluginApi::V1::Host.new(
      manifest: manifest,
      event_bus: Mcweb::Events
    )
  end

  test "finds users by id or public id through an allow-listed immutable snapshot" do
    by_id = @api.identity.find_user(id: @user.id)
    by_public_id = @api.identity.find_user(public_id: @user.public_id)

    assert_predicate by_id, :success?
    assert_equal by_id.value, by_public_id.value
    assert_equal(
      %w[created_at display_name id public_id schema_version status type updated_at username],
      by_id.value.keys.sort
    )
    assert_equal "identity.user", by_id.value.fetch("type")
    assert_equal "Visible Member", by_id.value.fetch("display_name")
    assert_equal "active", by_id.value.fetch("status")
    assert_predicate by_id, :frozen?
    assert_predicate by_id.value, :frozen?
    assert_predicate by_id.value.fetch("username"), :frozen?
    assert_raises(FrozenError) { by_id.value["username"] = "changed" }
    refute contains_active_record?(by_id.value)
    refute_includes by_id.value.keys, "email"
    refute_includes by_id.value.keys, "password_digest"
    refute_includes by_id.value.keys, "ban_reason"
  end

  test "reports effective banned and deleted account status without private details" do
    banned = create_user
    banned.ban!(reason: "private moderation reason", expires_at: 1.day.from_now)

    banned_status = @api.identity.user_status(public_id: banned.public_id)
    assert_predicate banned_status, :success?
    assert_equal "banned", banned_status.value.fetch("status")
    assert banned_status.value.fetch("banned")
    refute banned_status.value.fetch("deleted")
    refute banned_status.value.fetch("active")
    refute banned_status.value.fetch("session_eligible")
    refute_includes banned_status.value.keys, "ban_reason"
    refute_includes banned_status.value.keys, "ban_expires_at"

    deleted = create_user
    deleted.soft_delete!
    deleted_status = @api.identity.user_status(id: deleted.id)
    assert_equal "deleted", deleted_status.value.fetch("status")
    assert deleted_status.value.fetch("deleted")
    refute deleted_status.value.fetch("banned")
    refute deleted_status.value.fetch("session_eligible")
  end

  test "updates allow-listed user profile fields through the audited core service" do
    result = @api.identity.update_user(
      actor: @user,
      user: @user,
      attributes: {
        display_name: "Updated Member",
        locale: "en",
        time_zone: "UTC",
        account_type: "owner"
      }
    )

    assert_predicate result, :success?
    assert result.value.fetch("changed")
    assert_equal "Updated Member", result.value.dig("user", "display_name")
    assert_equal "member", @user.reload.account_type
    audit = AuditLog.where(
      action: "identity.user.profile_updated",
      resource_type: "User",
      resource_id: @user.id
    ).order(:id).last
    assert audit
    assert_equal %w[display_name locale time_zone],
                 audit.metadata.fetch("changed_fields")
    refute contains_active_record?(result.value)

    denied = @api.identity.update_user(
      actor: create_user,
      user: @user,
      attributes: { display_name: "Forbidden" }
    )
    assert_predicate denied, :failure?
    assert_equal "forbidden", denied.code
    assert_equal "Updated Member", @user.reload.display_name
  end

  test "lists global groups and user memberships as deeply frozen snapshots" do
    primary = Community::UserGroup.create!(
      name: "Operators",
      priority: 20,
      color_hex: "#123456",
      banner_text: "Ops",
      permissions: %w[forum.topics.lock identity.users.read]
    )
    secondary = Community::UserGroup.create!(
      name: "Members",
      priority: 10,
      is_primary_default: true,
      permissions: [ "forum.read" ]
    )
    Community::GroupMembership.create!(
      user: @user,
      user_group: primary,
      is_primary: true
    )

    catalog = @api.identity.groups
    assert_predicate catalog, :success?
    assert_includes catalog.value.pluck("id"), primary.id
    assert_includes catalog.value.pluck("id"), secondary.id
    assert_operator catalog.value.index { |group| group["id"] == primary.id },
                    :<,
                    catalog.value.index { |group| group["id"] == secondary.id }

    memberships = @api.identity.user_groups(public_id: @user.public_id)
    assert_predicate memberships, :success?
    assert_equal [ primary.id ], memberships.value.pluck("id")
    assert memberships.value.first.fetch("primary")
    assert_equal %w[forum.topics.lock identity.users.read],
                 memberships.value.first.fetch("permission_keys")
    assert_predicate memberships.value, :frozen?
    assert_predicate memberships.value.first, :frozen?
    assert_predicate memberships.value.first.fetch("permission_keys"), :frozen?
    assert_predicate memberships.value.first.fetch("permission_keys").first, :frozen?
    refute contains_active_record?(memberships.value)
  end

  test "mutates global group membership through canonical permission and audit checks" do
    actor = create_user
    grant_permission(actor, "identity.groups.members.assign")
    primary = Community::UserGroup.create!(
      name: "Plugin Members",
      priority: 20,
      permissions: []
    )
    secondary = Community::UserGroup.create!(
      name: "Plugin Guests",
      priority: 10,
      permissions: []
    )
    Community::GroupMembership.create!(
      user: @user,
      user_group: secondary,
      is_primary: true
    )

    added = @api.identity.add_group_member(
      actor:,
      user: @user,
      group: primary
    )
    assert_predicate added, :success?
    assert added.value.fetch("member")
    refute added.value.dig("group", "primary")

    made_primary = @api.identity.set_primary_group(
      actor:,
      user: @user,
      group: primary.id
    )
    assert_predicate made_primary, :success?
    assert made_primary.value.dig("group", "primary")
    refute Community::GroupMembership.find_by!(
      user: @user,
      user_group: secondary
    ).is_primary?

    removed = @api.identity.remove_group_member(
      actor:,
      user: @user,
      group: primary
    )
    assert_predicate removed, :success?
    refute removed.value.fetch("member")
    refute contains_active_record?(removed.value)

    assert_equal(
      %w[
        identity.group.member_added
        identity.group.primary_changed
        identity.group.member_removed
      ],
      AuditLog.where(actor:).order(:id).pluck(:action)
    )
  end

  test "returns effective permission decisions with role and group grant sources" do
    permission_key = "forum.topics.lock"
    group_only_key = "forum.posts.hide"
    grant_permission(@user, permission_key)
    group = Community::UserGroup.create!(
      name: "Moderators",
      priority: 50,
      permissions: [ permission_key, group_only_key ]
    )
    Community::GroupMembership.create!(
      user: @user,
      user_group: group,
      is_primary: true
    )

    decision = @api.identity.permission(
      public_id: @user.public_id,
      key: permission_key
    )
    assert_predicate decision, :success?
    assert decision.value.fetch("allowed")
    assert decision.value.fetch("account_eligible")
    assert_equal "granted_by_role_and_group", decision.value.fetch("reason")
    assert_equal %w[group role], decision.value.fetch("sources").pluck("type").sort
    group_source = decision.value.fetch("sources").find { |source| source["type"] == "group" }
    assert group_source.fetch("primary")
    assert_predicate decision.value.fetch("sources"), :frozen?
    assert decision.value.fetch("sources").all?(&:frozen?)
    refute contains_active_record?(decision.value)

    group_decision = @api.identity.permission(id: @user.id, key: group_only_key)
    assert group_decision.value.fetch("allowed")
    assert_equal "granted_by_group", group_decision.value.fetch("reason")
    assert_equal [ "group" ], group_decision.value.fetch("sources").pluck("type")

    denied = @api.identity.permission(id: @user.id, key: "forum.topics.archive")
    refute denied.value.fetch("allowed")
    assert_equal "not_granted", denied.value.fetch("reason")
    assert_empty denied.value.fetch("sources")
  end

  test "account eligibility overrides underlying grants with an explicit reason" do
    permission_key = "forum.topics.lock"
    grant_permission(@user, permission_key)
    @user.ban!(reason: "test")

    banned = @api.identity.permission(id: @user.id, key: permission_key)
    refute banned.value.fetch("allowed")
    refute banned.value.fetch("account_eligible")
    assert_equal "account_banned", banned.value.fetch("reason")
    assert_equal [ "role" ], banned.value.fetch("sources").pluck("type")

    deleted = create_user
    grant_permission(deleted, permission_key)
    deleted.soft_delete!
    deleted_decision = @api.identity.permission(id: deleted.id, key: permission_key)
    refute deleted_decision.value.fetch("allowed")
    assert_equal "account_deleted", deleted_decision.value.fetch("reason")
  end

  test "validates selectors limits and permission keys without leaking lookup state" do
    [
      @api.identity.find_user,
      @api.identity.find_user(id: @user.id, public_id: @user.public_id),
      @api.identity.find_user(id: 0),
      @api.identity.find_user(public_id: ""),
      @api.identity.groups(limit: 0),
      @api.identity.permission(id: @user.id),
      @api.identity.permission(id: @user.id, key: "Invalid Permission")
    ].each do |result|
      assert_predicate result, :failure?
      assert_equal "invalid_argument", result.code
      assert_predicate result, :frozen?
    end

    missing_by_id = @api.identity.find_user(id: User.maximum(:id).to_i + 10_000)
    missing_by_public_id = @api.identity.find_user(public_id: "missing-user")
    assert_equal "not_found", missing_by_id.code
    assert_equal "not_found", missing_by_public_id.code
    assert_equal missing_by_id.error, missing_by_public_id.error
  end

  private

  def manifest
    Mcweb::Plugins::Manifest.from_hash({
      id: "acme/identity-api",
      name: "Identity API",
      version: "1.0.0",
      api_version: "1",
      capabilities: %w[
        identity.groups.read
        identity.groups.members.write
        identity.permissions.read
        identity.users.read
        identity.users.write
      ]
    })
  end

  def contains_active_record?(value)
    case value
    when ActiveRecord::Base
      true
    when Hash
      value.any? { |key, item| contains_active_record?(key) || contains_active_record?(item) }
    when Array
      value.any? { |item| contains_active_record?(item) }
    else
      false
    end
  end
end
