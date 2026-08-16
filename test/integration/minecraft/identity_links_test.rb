# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Minecraft
  class IdentityLinksTest < ActionDispatch::IntegrationTest
    setup do
      @user = create_user
      @link = create_bound_account(user: @user, username: "OwnedAccount")
      @other_link = create_bound_account(user: create_user, username: "OtherAccount")
      sign_in_as(@user)
    end

    test "link page exposes owner-scoped unlink authorization data" do
      get minecraft_link_path

      assert_response :success
      account = inertia.props.deep_symbolize_keys.fetch(:accounts).sole
      assert_equal @link.id, account.fetch(:id)
      assert_equal minecraft_identity_link_path(@link), account.fetch(:unlinkUrl)
      assert_equal "OwnedAccount", account.fetch(:unlinkConfirmation)
      assert_equal @link.lock_version, account.fetch(:lockVersion)
      refute_includes account.to_json, "OtherAccount"
    end

    test "signed-in owner can unlink while foreign accounts remain undiscoverable" do
      delete minecraft_identity_link_path(@other_link), params: unlink_params(@other_link, "OtherAccount", "foreign")
      assert_response :not_found
      assert_nil @other_link.reload.unlinked_at

      delete minecraft_identity_link_path(@link), params: unlink_params(@link, "OwnedAccount", "owner-unlink")
      assert_redirected_to minecraft_link_path
      assert_equal I18n.t("mcweb.flash.minecraft_identity_unlinked"), flash[:notice]
      assert_not_nil @link.reload.unlinked_at
      assert AuditLog.exists?(action: "minecraft.identity_unlinked", actor: @user)
    end

    test "stale and confirmation failures are localized without unlinking" do
      stale_version = @link.lock_version
      @link.touch

      delete minecraft_identity_link_path(@link), params: unlink_params(
        @link,
        "OwnedAccount",
        "stale",
        lock_version: stale_version
      )
      assert_redirected_to minecraft_link_path
      assert_equal I18n.t("mcweb.services.errors.minecraft_identity_unlink_stale"), flash[:alert]

      delete minecraft_identity_link_path(@link), params: unlink_params(@link, "WrongAccount", "wrong")
      assert_redirected_to minecraft_link_path
      assert_equal I18n.t("mcweb.services.errors.minecraft_identity_unlink_confirmation_mismatch"), flash[:alert]
      assert_nil @link.reload.unlinked_at
    end

    test "unlink endpoint applies account and IP aware abuse throttling with retry guidance" do
      SiteSetting.set("security.rate_limits.minecraft_identity_unlink.account_limit", "1")
      SiteSetting.set("security.rate_limits.minecraft_identity_unlink.ip_limit", "30")

      Mcweb::DeveloperMode.stub(:allow?, false) do
        delete minecraft_identity_link_path(@link), params: unlink_params(@link, "Wrong", "first-attempt")
        assert_redirected_to minecraft_link_path

        delete minecraft_identity_link_path(@link), params: unlink_params(@link, "OwnedAccount", "second-attempt")
      end

      assert_redirected_to minecraft_link_path
      assert_equal I18n.t("mcweb.flash.rate_limited"), flash[:alert]
      assert_operator response.headers.fetch("Retry-After").to_i, :>, 0
      assert_nil @link.reload.unlinked_at
    end

    private

    def unlink_params(link, confirmation, key, lock_version: link.lock_version)
      {
        confirmation: confirmation,
        lock_version: lock_version,
        idempotency_key: key
      }
    end

    def create_bound_account(user:, username:)
      profile = Minecraft::PlayerProfile.create!
      Minecraft::PlayerIdentity.create!(
        player_profile: profile,
        platform: "java",
        external_uuid: SecureRandom.uuid,
        username: username,
        identity_type: "java",
        valid_from: Time.current
      )
      Minecraft::IdentityLink.create!(user: user, player_profile: profile, linked_at: Time.current)
    end
  end
end
