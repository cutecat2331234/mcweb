# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"
require "chunky_png"

module Minecraft
  class PrimaryAccountsTest < ActionDispatch::IntegrationTest
    setup do
      @user = create_user
      @first_link, @first_identity = create_bound_account(user: @user, username: "First")
      @second_link, @second_identity = create_bound_account(user: @user, username: "Second")
      @inactive_link, = create_bound_account(user: @user, username: "Inactive")
      @inactive_link.unlink!
      @other_link, = create_bound_account(user: create_user, username: "Other")
      SiteSetting.set("minecraft.primary_account.switch_policy", "immediate")
      SiteSetting.set("minecraft.primary_account.cooldown_seconds", "0")
      SiteSetting.set("minecraft.primary_account.request_expiry_hours", "72")
      sign_in_as(@user)
    end

    test "original link page lists only the member's active local account data" do
      attach_avatar(@second_identity)

      get minecraft_link_path

      assert_response :success
      assert_equal "Minecraft/Link/Show", inertia.component
      props = inertia.props.deep_symbolize_keys
      accounts = props.fetch(:accounts)
      assert_equal 2, accounts.length
      assert_equal [ "First", "Second" ], accounts.pluck(:username)
      assert_equal [ @first_identity.external_uuid, @second_identity.external_uuid ], accounts.pluck(:uuid)
      assert_equal true, accounts.first.fetch(:primary)
      assert_equal false, accounts.second.fetch(:primary)
      assert_equal "/minecraft/default-skin-avatar.svg", accounts.first.fetch(:avatarUrl)
      assert_equal minecraft_cached_skin_path(@second_identity, variant: "avatar"),
        accounts.second.fetch(:avatarUrl)
      serialized = accounts.to_json
      refute_includes serialized, "Inactive"
      refute_includes serialized, "Other"
      refute_match(/textures\.minecraft\.net|sessionserver\.mojang\.com|crafatar/i, serialized)
      assert_equal "immediate", props.dig(:primaryPolicy, :switchPolicy)
    end

    test "member can switch only to an active link owned by that member" do
      post minecraft_primary_account_path(@second_link), params: {
        reason: "Use this account",
        idempotency_key: "link-page-switch"
      }
      assert_redirected_to minecraft_link_path
      assert_predicate @second_link.reload, :primary_account?

      post minecraft_primary_account_path(@inactive_link), params: {
        idempotency_key: "inactive-link"
      }
      assert_redirected_to minecraft_link_path
      assert_predicate @second_link.reload, :primary_account?
      refute_predicate @inactive_link.reload, :primary_account?

      post minecraft_primary_account_path(@other_link), params: {
        idempotency_key: "foreign-link"
      }
      assert_redirected_to minecraft_link_path
      assert_predicate @second_link.reload, :primary_account?
      assert_predicate @other_link.reload, :primary_account?
      assert_equal 1, Minecraft::PrimaryAccountChangeEvent.where(user: @user).count
    end

    test "staff approval request appears on the same page and can be cancelled" do
      SiteSetting.set("minecraft.primary_account.switch_policy", "staff_approval")

      post minecraft_primary_account_path(@second_link), params: {
        reason: "Please verify this account",
        idempotency_key: "link-page-request"
      }
      assert_redirected_to minecraft_link_path
      request_record = Minecraft::PrimaryAccountChangeRequest.find_by!(user: @user)
      assert_predicate request_record, :pending?

      get minecraft_link_path
      assert_response :success
      pending = inertia.props.deep_symbolize_keys.fetch(:pendingRequest)
      assert_equal request_record.id, pending.fetch(:id)
      assert_equal "Second", pending.fetch(:targetAccount)
      assert_equal request_record.lock_version, pending.fetch(:lockVersion)

      delete minecraft_primary_account_change_request_path(request_record), params: {
        lock_version: request_record.lock_version
      }
      assert_redirected_to minecraft_link_path
      assert_predicate request_record.reload, :cancelled?
      assert_predicate @first_link.reload, :primary_account?
      refute_predicate @second_link.reload, :primary_account?
    end

    private

    def create_bound_account(user:, username:)
      profile = Minecraft::PlayerProfile.create!
      identity = Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      link = Minecraft::IdentityLink.create!(
        user: user,
        player_profile: profile,
        linked_at: Time.current
      )
      [ link, identity ]
    end

    def attach_avatar(identity)
      payload = ChunkyPNG::Image.new(16, 16, ChunkyPNG::Color::WHITE).to_blob
      identity.skin_avatar_file.attach(
        io: StringIO.new(payload),
        filename: "avatar.png",
        content_type: "image/png"
      )
    end
  end
end
