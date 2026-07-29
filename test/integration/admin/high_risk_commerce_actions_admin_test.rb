# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  class HighRiskCommerceActionsAdminTest < ActionDispatch::IntegrationTest
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @membership_type = Commerce::MembershipType.create!(
        slug: "admin-risk-#{SecureRandom.hex(4)}",
        name: "Admin risk membership",
        duration_mode: "fixed_days",
        duration_days: 30,
        game_permission_enabled: false,
        active: true
      )
      @product = Commerce::Product.create!(
        name: "Admin manual entitlement",
        slug: "admin-entitlement-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        fulfillment_config: { entitlement_days: 7 }
      )
      grant_permission(@actor, "admin.access")
      grant_permission(@actor, "store.entitlements.read")
      grant_permission(@actor, "store.entitlements.grant")
      grant_admin_module(@actor, "store")
      sign_in_as(@actor)
    end

    test "membership form uses JSON preview and execution without redirecting on validation failure" do
      get new_admin_store_user_membership_path
      assert_response :success
      props = inertia.props.deep_symbolize_keys
      assert_equal authorize_grant_admin_store_user_memberships_path,
        props.fetch(:authorizationUrl)
      assert_equal admin_store_user_memberships_path, props.fetch(:submitUrl)

      request_id = SecureRandom.uuid
      payload = {
        user_membership: {
          username: @target.username,
          membership_type_id: @membership_type.id,
          grant_game_permissions: false
        },
        request_id: request_id,
        reason: "Verified admin support grant"
      }
      post authorize_grant_admin_store_user_memberships_path,
        params: payload,
        as: :json
      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      authorization = JSON.parse(response.body)
      assert_equal request_id, authorization.fetch("request_id")
      assert authorization.fetch("preview_items").any?

      assert_no_difference -> { Commerce::UserMembership.count } do
        post admin_store_user_memberships_path,
          params: payload.merge(
            authorization_token: authorization.fetch("authorization_token"),
            confirmation: "WRONG"
          ),
          as: :json
      end
      assert_response :unprocessable_entity
      assert_equal I18n.t("mcweb.services.errors.high_risk_confirmation_invalid"),
        JSON.parse(response.body).fetch("error")
      assert_nil response.location

      assert_difference -> { Commerce::UserMembership.count }, 1 do
        post admin_store_user_memberships_path,
          params: payload.merge(
            authorization_token: authorization.fetch("authorization_token"),
            confirmation: authorization.fetch("confirmation")
          ),
          as: :json
      end
      assert_response :success
      result = JSON.parse(response.body)
      assert_equal false, result.fetch("idempotent")
      assert_match %r{/admin/store/user_memberships/\d+\z}, result.fetch("redirect_url")
    end

    test "digital entitlement grant and revoke expose the same two-phase API contract" do
      request_id = SecureRandom.uuid
      payload = {
        user_entitlement: {
          username: @target.username,
          product_id: @product.id
        },
        request_id: request_id,
        reason: "Verified entitlement restoration"
      }
      post authorize_grant_admin_store_user_entitlements_path,
        params: payload,
        as: :json
      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      authorization = JSON.parse(response.body)

      post admin_store_user_entitlements_path,
        params: payload.merge(
          authorization_token: authorization.fetch("authorization_token"),
          confirmation: authorization.fetch("confirmation")
        ),
        as: :json
      assert_response :success
      entitlement = Commerce::UserEntitlement.order(:id).last
      assert entitlement.currently_active?

      post authorize_revoke_admin_store_user_entitlement_path(entitlement),
        params: {
          request_id: SecureRandom.uuid,
          reason: "Revoke without dedicated permission"
        },
        as: :json
      assert_redirected_to root_path

      grant_permission(@actor, "store.entitlements.revoke")
      revoke_request_id = SecureRandom.uuid
      revoke_payload = {
        request_id: revoke_request_id,
        reason: "Verified entitlement revocation"
      }
      post authorize_revoke_admin_store_user_entitlement_path(entitlement),
        params: revoke_payload,
        as: :json
      assert_response :success
      revoke_authorization = JSON.parse(response.body)

      post revoke_admin_store_user_entitlement_path(entitlement),
        params: revoke_payload.merge(
          authorization_token: revoke_authorization.fetch("authorization_token"),
          confirmation: revoke_authorization.fetch("confirmation")
        ),
        as: :json
      assert_response :success
      assert entitlement.reload.revoked_at?
      assert_equal admin_store_user_entitlements_path,
        JSON.parse(response.body).fetch("redirect_url")
    end

    test "order bulk endpoint returns local JSON errors and never partially updates changed targets" do
      grant_permission(@actor, "store.orders.read")
      grant_permission(@actor, "store.orders.cancel")
      first = create_order
      second = create_order
      request_id = SecureRandom.uuid
      payload = {
        order_ids: [ first.public_id, second.public_id ],
        action_type: "cancel_pending",
        request_id: request_id,
        reason: "Duplicate orders cancelled by support"
      }

      post authorize_high_risk_action_admin_store_orders_path,
        params: payload,
        as: :json
      assert_response :success
      assert_includes response.headers.fetch("Cache-Control"), "no-store"
      authorization = JSON.parse(response.body)
      second.update!(status: "paid")

      patch bulk_update_admin_store_orders_path,
        params: payload.merge(
          authorization_token: authorization.fetch("authorization_token"),
          confirmation: authorization.fetch("confirmation")
        ),
        as: :json
      assert_response :unprocessable_entity
      assert_nil response.location
      assert first.reload.pending?
      assert second.reload.paid?
      assert_not Commerce::HighRiskOperation.exists?(request_id: request_id)
    end

    private

    def create_order
      Commerce::Order.create!(
        public_id: "ord_admin_risk_#{SecureRandom.hex(7)}",
        order_number: "ARISK#{SecureRandom.hex(5).upcase}",
        user: @target,
        status: "pending",
        subtotal_cents: 1_000,
        total_cents: 1_000,
        currency: "CNY"
      )
    end
  end
end
