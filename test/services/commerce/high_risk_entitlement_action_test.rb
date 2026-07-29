# frozen_string_literal: true

require "test_helper"

module Commerce
  class HighRiskEntitlementActionTest < ActiveSupport::TestCase
    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @product = Commerce::Product.create!(
        name: "Manual download",
        slug: "manual-download-#{SecureRandom.hex(5)}",
        product_type: "digital",
        status: "active",
        price_cents: 2_000,
        currency: "CNY",
        fulfillment_config: { entitlement_days: 14 }
      )
      @request_id = SecureRandom.uuid
      @reason = "Recovery after verified fulfillment incident"
      grant_permission(@actor, "store.entitlements.grant")
    end

    test "grant and revoke digital entitlement use separate permission and immutable operation records" do
      grant_authorization = authorize_grant
      granted = Commerce::HighRiskEntitlementAction.call(
        **grant_attributes,
        authorization_token: grant_authorization[:authorization_token],
        confirmation: grant_authorization[:confirmation]
      )

      assert_predicate granted, :success?, granted.error
      entitlement = granted.value[:entitlement]
      assert entitlement.currently_active?
      assert_in_delta 14.days.from_now, entitlement.expires_at, 5.seconds
      assert_equal @reason, granted.value[:operation].reason
      assert AuditLog.by_action("commerce.entitlement_grant")
        .where("metadata ->> 'request_id' = ?", @request_id)
        .exists?

      revoke_request_id = SecureRandom.uuid
      denied = Commerce::HighRiskEntitlementAction.authorize(
        actor: @actor,
        action: "entitlement.revoke",
        entitlement: entitlement,
        request_id: revoke_request_id,
        reason: @reason
      )
      assert_predicate denied, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error

      grant_permission(@actor, "store.entitlements.revoke")
      authorization = Commerce::HighRiskEntitlementAction.authorize(
        actor: @actor,
        action: "entitlement.revoke",
        entitlement: entitlement,
        request_id: revoke_request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error

      revoke_attributes = {
        actor: @actor,
        action: "entitlement.revoke",
        entitlement: entitlement,
        request_id: revoke_request_id,
        reason: @reason,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      }
      revoked = Commerce::HighRiskEntitlementAction.call(**revoke_attributes)
      replay = Commerce::HighRiskEntitlementAction.call(**revoke_attributes)

      assert_predicate revoked, :success?, revoked.error
      assert_predicate replay, :success?, replay.error
      assert replay.value[:idempotent]
      assert entitlement.reload.revoked_at?
      assert_equal 1,
        Commerce::HighRiskOperation.where(action: "entitlement.revoke", request_id: revoke_request_id).count
    end

    test "changed product configuration invalidates grant preview without creating entitlement" do
      authorization = authorize_grant
      @product.update!(
        fulfillment_config: { entitlement_days: 30 }
      )

      assert_no_difference -> { Commerce::UserEntitlement.count } do
        result = Commerce::HighRiskEntitlementAction.call(
          **grant_attributes,
          authorization_token: authorization[:authorization_token],
          confirmation: authorization[:confirmation]
        )
        assert_predicate result, :failure?
        assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"),
          result.error
      end
      assert_not Commerce::HighRiskOperation.exists?(request_id: @request_id)
    end

    test "product must define a digital entitlement duration" do
      @product.update!(fulfillment_config: {})
      result = Commerce::HighRiskEntitlementAction.authorize(**grant_attributes)

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.entitlement_not_configured"), result.error
    end

    private

    def grant_attributes
      {
        actor: @actor,
        action: "entitlement.grant",
        user: @target,
        product: @product,
        request_id: @request_id,
        reason: @reason
      }
    end

    def authorize_grant
      result = Commerce::HighRiskEntitlementAction.authorize(**grant_attributes)
      assert_predicate result, :success?, result.error
      result.value
    end
  end

  class HighRiskEntitlementActionConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @actor = create_user(account_type: "staff")
      @target = create_user
      @product = Commerce::Product.create!(
        name: "Concurrent digital entitlement",
        slug: "concurrent-entitlement-#{SecureRandom.hex(5)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY",
        fulfillment_config: { entitlement_days: 7 }
      )
      grant_permission(@actor, "store.entitlements.grant")
      @request_id = SecureRandom.uuid
      @reason = "Concurrent entitlement grant verification"
      authorization = Commerce::HighRiskEntitlementAction.authorize(
        actor: @actor,
        action: "entitlement.grant",
        user: @target,
        product: @product,
        request_id: @request_id,
        reason: @reason
      )
      assert_predicate authorization, :success?, authorization.error
      @authorization = authorization.value
    end

    teardown do
      AuditLog.where("metadata ->> 'request_id' = ?", @request_id).delete_all
      Commerce::HighRiskOperation.where(request_id: @request_id).delete_all
      Commerce::UserEntitlement.where(
        user_id: @target.id,
        store_product_id: @product.id
      ).delete_all
      Commerce::Product.where(id: @product.id).delete_all
      User.where(id: [ @actor.id, @target.id ]).destroy_all
    end

    test "concurrent identical grants create one digital entitlement" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << Commerce::HighRiskEntitlementAction.call(
              actor: User.find(@actor.id),
              action: "entitlement.grant",
              user: User.find(@target.id),
              product: Commerce::Product.find(@product.id),
              request_id: @request_id,
              reason: @reason,
              authorization_token: @authorization[:authorization_token],
              confirmation: @authorization[:confirmation]
            )
          end
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      assert responses.all?(&:success?), responses.map(&:error).inspect
      assert_equal 1, responses.count { |result| result.value[:idempotent] }
      assert_equal 1, responses.count { |result| !result.value[:idempotent] }
      assert_equal 1, Commerce::UserEntitlement.where(
        user_id: @target.id,
        store_product_id: @product.id
      ).count
      assert_equal 1, Commerce::HighRiskOperation.where(request_id: @request_id).count
    end
  end
end
