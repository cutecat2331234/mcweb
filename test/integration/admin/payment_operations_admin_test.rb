# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Store
    class PaymentOperationsAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "store.orders.read")
        sign_in_as(@admin)

        customer = create_user(email: "payment-customer-private@example.com")
        @order = Commerce::Order.create!(
          public_id: "ord_payment_ops_#{SecureRandom.hex(6)}",
          order_number: "PAYMENT-OPS-#{SecureRandom.hex(4).upcase}",
          user: customer,
          status: "paid",
          subtotal_cents: 3_000,
          discount_cents: 0,
          total_cents: 3_000,
          currency: "CNY"
        )
        @payment = Payments::Record.create!(
          order: @order,
          provider: "stripe",
          status: "succeeded",
          amount_cents: 3_000,
          currency: "CNY",
          provider_payment_id: "pi_admin_secret_reference_1234",
          metadata: {
            "orphaned" => true,
            "orphan_reason" => "order_cancelled",
            "customer_email" => customer.email,
            "secret_key" => "sk_test_admin_must_not_render"
          }
        )
        @failed_webhook = Payments::WebhookEvent.create!(
          provider: "stripe",
          event_id: "evt_admin_failed_secret_5678",
          event_type: "payment_intent.payment_failed",
          status: "failed",
          error_message: "#{customer.email} sk_test_admin_must_not_render",
          payload: { "customer_email" => customer.email, "secret" => "whsec_admin_must_not_render" }
        )
        @stale_webhook = Payments::WebhookEvent.create!(
          provider: "stripe",
          event_id: "evt_admin_stale_secret_9012",
          event_type: "payment_intent.processing",
          status: "processing",
          payload: { "secret" => "whsec_admin_must_not_render" },
          created_at: 30.minutes.ago,
          updated_at: 30.minutes.ago
        )
        @refund = Commerce::Refund.create!(
          order: @order,
          payment_record: @payment,
          amount_cents: 750,
          status: "approved",
          reason: "Private request from #{customer.email}",
          provider_refund_id: "re_admin_secret_reference_3456",
          provider_status: "pending",
          provider_error_code: "provider_pending",
          provider_metadata: {
            "customer_email" => customer.email,
            "secret" => "sk_test_admin_must_not_render"
          },
          processing_started_at: 10.minutes.ago
        )
        Payments::ProviderConfig.find_or_initialize_by(provider: "stripe").tap do |config|
          config.enabled = true
          config.credentials = {
            "secret_key" => "sk_test_admin_must_not_render",
            "webhook_secret" => "whsec_admin_must_not_render"
          }
          config.save!
          mark_stripe_provider_connection_tested!(config)
        end
      end

      test "payment and orphan views expose only allowlisted operations data" do
        assert_no_changes -> { Payments::Record.count } do
          get admin_store_payment_operations_path,
            params: {
              view: "payments",
              provider: "stripe",
              status: "succeeded",
              q: @order.order_number
            }
        end

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "Admin/Store/PaymentOperations/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        row = props[:rows].find { |item| item[:id] == @payment.id }

        assert_equal "pi_••••1234", row[:provider_reference]
        assert_equal @order.order_number, row[:order_number]
        assert props[:providerStatuses].any? { |item| item[:provider] == "stripe" && item[:checkout_ready] }
        assert_sensitive_values_absent(props)

        get admin_store_payment_operations_path, params: { view: "orphans", q: @order.order_number }
        assert_response :success
        orphan = inertia.props.deep_symbolize_keys[:rows].find { |item| item[:id] == @payment.id }
        assert orphan[:orphaned]
        assert_equal "order_cancelled", orphan[:orphan_reason]
      end

      test "webhook view filters failed processing and stale without returning payloads" do
        get admin_store_payment_operations_path, params: { view: "webhooks", status: "failed" }
        assert_response :success
        failed_rows = inertia.props.deep_symbolize_keys[:rows]
        assert_includes failed_rows.map { |row| row[:id] }, @failed_webhook.id
        assert failed_rows.find { |row| row[:id] == @failed_webhook.id }[:error_recorded]
        assert_sensitive_values_absent(inertia.props.deep_symbolize_keys)

        get admin_store_payment_operations_path, params: { view: "webhooks", status: "processing" }
        assert_response :success
        assert_includes inertia.props.deep_symbolize_keys[:rows].map { |row| row[:id] }, @stale_webhook.id

        get admin_store_payment_operations_path, params: { view: "webhooks", status: "stale" }
        assert_response :success
        stale_rows = inertia.props.deep_symbolize_keys[:rows]
        assert_equal [ @stale_webhook.id ], stale_rows.filter_map { |row| row[:id] if row[:id].in?([ @stale_webhook.id, @failed_webhook.id ]) }
        assert stale_rows.find { |row| row[:id] == @stale_webhook.id }[:stale]
      end

      test "refund view filters provider status and marks stale processing" do
        get admin_store_payment_operations_path,
          params: {
            view: "refunds",
            provider: "stripe",
            status: "stale",
            provider_status: "pending"
          }

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        row = props[:rows].find { |item| item[:id] == @refund.id }

        assert row[:stale]
        assert_equal "pending", row[:provider_status]
        assert_equal "re_••••3456", row[:provider_reference]
        assert_sensitive_values_absent(props)
      end

      test "payment records use server-side pagination" do
        41.times do |index|
          Payments::Record.create!(
            order: @order,
            provider: "stripe",
            status: "succeeded",
            amount_cents: 3_000,
            currency: "CNY",
            provider_payment_id: "pi_payment_ops_page_#{index}_#{SecureRandom.hex(4)}"
          )
        end

        get admin_store_payment_operations_path,
          params: {
            view: "payments",
            provider: "stripe",
            q: @order.order_number,
            page: 2
          }

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        assert_equal 2, props[:pagination][:page]
        assert_equal 2, props[:pagination][:pages]
        assert_equal 42, props[:pagination][:count]
        assert_equal 2, props[:rows].size
      end

      test "store module and order read permission are both required" do
        delete identity_session_path
        staff = create_user(account_type: "staff")
        grant_permission(staff, "admin.access")
        grant_admin_module(staff, "store")
        sign_in_as(staff)

        get admin_store_payment_operations_path

        assert_redirected_to root_path
      end

      private

      def assert_sensitive_values_absent(props)
        rendered = {
          rows: props[:rows],
          provider_statuses: props[:providerStatuses]
        }.to_json

        refute_includes rendered, "payment-customer-private@example.com"
        refute_includes rendered, "sk_test_admin_must_not_render"
        refute_includes rendered, "whsec_admin_must_not_render"
        refute_includes rendered, "pi_admin_secret_reference_1234"
        refute_includes rendered, "evt_admin_failed_secret_5678"
        refute_includes rendered, "re_admin_secret_reference_3456"
        refute_includes rendered, "metadata"
        refute_includes rendered, "payload"
      end
    end
  end
end
