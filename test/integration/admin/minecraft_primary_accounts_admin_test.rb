# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class MinecraftPrimaryAccountsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @operator = create_user(account_type: :admin)
      grant_permission(@operator, "admin.access")
      grant_admin_module(@operator, "minecraft")
      @member = create_user
      @first_link = create_bound_account(user: @member, username: "First")
      @second_link = create_bound_account(user: @member, username: "Second")
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "0")
      SiteSetting.set("minecraft.primary_account.request_expiry_hours", "72")
    end

    test "review permission exposes requests but not administrator override controls" do
      grant_permission(@operator, "minecraft.primary_accounts.review")
      @operator.reload
      request_record = ::Minecraft::RequestPrimaryAccountChange.call(
        user: @member,
        target_identity_link: @second_link,
        actor: @member,
        reason: "Please review",
        idempotency_key: "admin-review-request"
      ).value.fetch(:request)
      sign_in_as(@operator)

      get admin_minecraft_players_path
      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal true, props.dig(:primaryAccountPermissions, :review)
      assert_equal false, props.dig(:primaryAccountPermissions, :switchForUser)
      assert_equal 1, props.fetch(:primaryAccountRequests).length
      assert_empty props.fetch(:boundAccounts)

      patch admin_minecraft_primary_account_change_request_path(request_record), params: {
        decision: "approve",
        reason: "Binding verified",
        lock_version: request_record.lock_version,
        idempotency_key: "admin-review-decision"
      }
      assert_redirected_to admin_minecraft_players_path
      assert_predicate request_record.reload, :approved?
      assert_predicate @second_link.reload, :primary_account?

      post admin_minecraft_primary_account_path(user_id: @member.id), params: {
        identity_link_id: @first_link.id,
        reason: "Not authorized",
        idempotency_key: "reviewer-cannot-override"
      }
      assert_redirected_to root_path
      assert_predicate @second_link.reload, :primary_account?
    end

    test "override permission is independent and requires an audited reason" do
      grant_permission(@operator, "minecraft.primary_accounts.switch_for_user")
      @operator.reload
      sign_in_as(@operator)

      get admin_minecraft_players_path
      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal false, props.dig(:primaryAccountPermissions, :review)
      assert_equal true, props.dig(:primaryAccountPermissions, :switchForUser)
      assert_empty props.fetch(:primaryAccountRequests)
      assert_equal 2, props.fetch(:boundAccounts).length
      refute_match(
        /textures\.minecraft\.net|sessionserver\.mojang\.com|crafatar/i,
        props.fetch(:boundAccounts).to_json
      )

      post admin_minecraft_primary_account_path(user_id: @member.id), params: {
        identity_link_id: @second_link.id,
        reason: "",
        idempotency_key: "override-missing-reason"
      }
      assert_redirected_to admin_minecraft_players_path
      assert_predicate @first_link.reload, :primary_account?

      post admin_minecraft_primary_account_path(user_id: @member.id), params: {
        identity_link_id: @second_link.id,
        reason: "Verified account ownership",
        idempotency_key: "override-success"
      }
      assert_redirected_to admin_minecraft_players_path
      assert_predicate @second_link.reload, :primary_account?
      event = ::Minecraft::PrimaryAccountChangeEvent.find_by!(
        user: @member,
        change_source: "administrator_override"
      )
      assert_equal "Verified account ownership", event.reason
      assert_equal false, event.counts_for_cooldown
      audit = AuditLog.find_by!(
        action: "minecraft.primary_account_changed",
        actor: @operator,
        request_id: "override-success"
      )
      assert_equal @second_link.id, audit.metadata.fetch("to_identity_link_id")
    end

    test "Minecraft settings configure every switch strategy and bounded timing" do
      grant_permission(@operator, "minecraft.servers.manage")
      @operator.reload
      sign_in_as(@operator)

      patch admin_minecraft_settings_path, params: {
        primary_account_switch_policy: "administrator_only",
        primary_account_cooldown_seconds: "7200",
        primary_account_request_expiry_hours: "96"
      }
      assert_redirected_to admin_minecraft_settings_path
      assert_equal "administrator_only",
        SiteSetting.get("minecraft.primary_account.switch_policy")
      assert_equal "7200",
        SiteSetting.get("minecraft.primary_account.cooldown_seconds")
      assert_equal "96",
        SiteSetting.get("minecraft.primary_account.request_expiry_hours")

      patch admin_minecraft_settings_path, params: {
        primary_account_switch_policy: "unsupported"
      }
      assert_redirected_to admin_minecraft_settings_path
      assert_equal "administrator_only",
        SiteSetting.get("minecraft.primary_account.switch_policy")
    end

    private

    def create_bound_account(user:, username:)
      profile = ::Minecraft::PlayerProfile.create!
      ::Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      ::Minecraft::IdentityLink.create!(
        user: user,
        player_profile: profile,
        linked_at: Time.current
      )
    end
  end
end
