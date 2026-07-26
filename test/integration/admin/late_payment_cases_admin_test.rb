# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Store
    class LatePaymentCasesAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, Payments::LatePaymentCase::PERMISSION)
        sign_in_as(@admin)

        customer = create_user(email: "late-payment-private@example.com")
        @order = Commerce::Order.create!(
          public_id: "ord_late_admin_#{SecureRandom.hex(6)}",
          order_number: "LATE-ADMIN-#{SecureRandom.hex(5).upcase}",
          user: customer,
          status: "cancelled",
          subtotal_cents: 3_500,
          discount_cents: 0,
          total_cents: 3_500,
          currency: "CNY"
        )
        @payment = Payments::Record.create!(
          order: @order,
          provider: "stripe",
          status: "succeeded",
          amount_cents: 3_500,
          currency: "CNY",
          provider_payment_id: "pi_late_admin_secret_1234",
          metadata: {
            "orphaned" => true,
            "orphan_reason" => "order_cancelled",
            "customer_email" => customer.email,
            "secret_key" => "sk_test_late_admin_must_not_render"
          }
        )
        @event = verified_event
        @review_case = Payments::LatePaymentCase.enqueue_from_verified_webhook!(
          payment_record: @payment,
          webhook_event: @event,
          reason: "order_cancelled"
        )
      end

      test "the queue is filterable and returns only masked allowlisted data" do
        get admin_store_late_payment_cases_path,
          params: {
            status: "open",
            reason: "order_cancelled",
            provider: "stripe",
            q: @order.order_number
          }

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "Admin/Store/LatePaymentCases/Index", inertia.component
        props = inertia.props.deep_symbolize_keys
        row = props[:rows].find { |item| item[:id] == @review_case.id }

        assert_equal "pi_••••1234", row[:payment_reference]
        assert_equal "evt_••••5678", row[:webhook_reference]
        assert_equal @order.order_number, row[:order_number]
        assert_equal "order_cancelled", row[:reason]
        assert_equal "open", row[:status]
        assert row[:action][:token].present?
        assert_equal 1, props[:summary][:open]
        assert_sensitive_values_absent(props)
      end

      test "acknowledging through the controller records an audit without changing payment state" do
        token = Payments::LatePaymentReviewToken.issue(@review_case)
        payment_before = @payment.attributes.slice("status", "amount_cents", "provider_payment_id", "metadata")
        order_before = @order.attributes.slice("status", "total_cents")

        patch acknowledge_admin_store_late_payment_case_path(@review_case), params: {
          token: token,
          confirmation: @order.order_number,
          disposition: "contact_customer",
          note: "Provider payment verified; contact the customer before refunding."
        }

        assert_redirected_to admin_store_late_payment_cases_path
        assert @review_case.reload.acknowledged?
        assert_equal payment_before, @payment.reload.attributes.slice(*payment_before.keys)
        assert_equal order_before, @order.reload.attributes.slice(*order_before.keys)
        assert AuditLog.exists?(
          action: "admin.payment_late_payment_acknowledged",
          resource_type: "Payments::LatePaymentCase",
          resource_id: @review_case.id,
          actor_id: @admin.id
        )
      end

      test "admin and store access do not replace the dedicated permission" do
        delete identity_session_path
        staff = create_user
        grant_permission(staff, "admin.access")
        grant_permission(staff, "store.orders.read")
        sign_in_as(staff)

        get admin_store_late_payment_cases_path

        assert_redirected_to root_path
      end

      private

      def verified_event
        payload = {
          "type" => "checkout.session.completed",
          "data" => {
            "object" => {
              "id" => @payment.provider_payment_id,
              "object" => "checkout.session",
              "livemode" => false,
              "payment_status" => "paid",
              "amount_total" => @payment.amount_cents,
              "currency" => @payment.currency.downcase,
              "client_reference_id" => @order.public_id,
              "payment_intent" => "pi_late_admin_intent",
              "metadata" => {
                "payment_record_id" => @payment.id.to_s,
                "order_public_id" => @order.public_id
              }
            }
          }
        }
        Payments::WebhookEvent.create!(
          provider: "stripe",
          event_id: "evt_late_admin_secret_5678",
          event_type: "checkout.session.completed",
          status: "processed",
          payload: payload,
          payload_digest: Payments::WebhookPayload.digest(
            payload,
            event_type: "checkout.session.completed"
          ),
          verified_at: Time.current,
          processed_at: Time.current
        )
      end

      def assert_sensitive_values_absent(props)
        rendered = props.to_json

        refute_includes rendered, "late-payment-private@example.com"
        refute_includes rendered, "sk_test_late_admin_must_not_render"
        refute_includes rendered, "pi_late_admin_secret_1234"
        refute_includes rendered, "evt_late_admin_secret_5678"
        refute_includes rendered, "metadata"
        refute_includes rendered, "payload"
      end
    end
  end
end
