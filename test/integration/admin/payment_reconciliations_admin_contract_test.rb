# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Store
    class PaymentReconciliationsAdminContractTest < ActionDispatch::IntegrationTest
      PAYMENT_REFERENCE = "pi_provider_full_secret_1234"
      PAYMENT_CURSOR = "pi_cursor_full_secret_5678"
      REFUND_CURSOR = "re_cursor_full_secret_9012"
      PROCESSING_TOKEN = "processing_token_full_secret_3456"

      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(
          @admin,
          Payments::ReconciliationDiscrepancy::READ_PERMISSION
        )
        grant_permission(
          @admin,
          Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
        )
        grant_permission(
          @admin,
          Payments::RequestManualReconciliation::PERMISSION
        )
        sign_in_as(@admin)

        @provider_config = configure_stripe!
        @run = create_run
        @order, @payment = create_payment
        @discrepancy = create_discrepancy(
          run: @run,
          payment_record: @payment,
          order: @order
        )
      end

      test "read and review require separate dedicated permissions" do
        delete identity_session_path
        reader = create_user
        grant_permission(reader, "admin.access")
        grant_permission(
          reader,
          Payments::ReconciliationDiscrepancy::READ_PERMISSION
        )
        sign_in_as(reader)

        get admin_store_payment_reconciliations_path

        assert_response :success
        props = inertia.props.deep_symbolize_keys
        refute props[:reviewEnabled]
        refute props.dig(:manualTrigger, :allowed)
        refute props.dig(:manualTrigger, :ready)
        assert_nil props.dig(:manualTrigger, :url)
        assert_nil props.dig(:manualTrigger, :authorizationUrl)
        assert_nil props.dig(:manualTrigger, :token)
        row = props[:rows].find { |item| item[:id] == @discrepancy.public_id }
        refute row.key?(:action)

        patch review_admin_store_payment_reconciliation_path(@discrepancy),
          params: valid_review_params(
            token: Payments::ReconciliationReviewToken.issue(@discrepancy)
          )

        assert_redirected_to root_path
        assert @discrepancy.reload.open?

        assert_no_enqueued_jobs do
          post trigger_admin_store_payment_reconciliations_path,
            params: {
              date: "2026-07-20",
              confirmation: "RECONCILE 2026-07-20 UTC",
              token: Payments::ManualReconciliationToken.issue(
                actor: reader,
                config: @provider_config,
                date: Date.new(2026, 7, 20)
              )
            }
        end

        assert_redirected_to root_path

        delete identity_session_path
        reviewer_without_read = create_user
        grant_permission(reviewer_without_read, "admin.access")
        grant_permission(
          reviewer_without_read,
          Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
        )
        sign_in_as(reviewer_without_read)

        get admin_store_payment_reconciliations_path

        assert_redirected_to root_path
      end

      test "review permission alone cannot authorize or queue a manual run" do
        delete identity_session_path
        reviewer = create_user
        grant_permission(reviewer, "admin.access")
        grant_permission(
          reviewer,
          Payments::ReconciliationDiscrepancy::READ_PERMISSION
        )
        grant_permission(
          reviewer,
          Payments::ReconciliationDiscrepancy::REVIEW_PERMISSION
        )
        sign_in_as(reviewer)

        travel_to Time.utc(2026, 7, 26, 12) do
          get admin_store_payment_reconciliations_path
          manual = inertia.props.deep_symbolize_keys.fetch(:manualTrigger)
          refute manual[:allowed]
          refute manual[:ready]

          post manual_authorization_admin_store_payment_reconciliations_path,
            params: { date: "2026-07-25" },
            as: :json
          assert_redirected_to root_path

          assert_no_enqueued_jobs do
            post trigger_admin_store_payment_reconciliations_path,
              params: {
                date: "2026-07-25",
                confirmation: "RECONCILE 2026-07-25 UTC",
                token: Payments::ManualReconciliationToken.issue(
                  actor: reviewer,
                  config: @provider_config,
                  date: Date.new(2026, 7, 25)
                )
              }
          end
          assert_redirected_to root_path
        end
      end

      test "index is no-store and issues review tokens only for open rows" do
        acknowledged = create_discrepancy(
          run: @run,
          status: "acknowledged",
          suffix: "acknowledged"
        )
        ignored = create_discrepancy(
          run: @run,
          status: "ignored",
          suffix: "ignored"
        )
        resolved = create_discrepancy(
          run: @run,
          status: "resolved",
          suffix: "resolved"
        )

        travel_to Time.utc(2026, 7, 26, 12) do
          get admin_store_payment_reconciliations_path

          assert_response :success
          assert_equal "no-store", response.headers["Cache-Control"]
          assert_equal "Admin/Store/PaymentReconciliations/Index", inertia.component
          props = inertia.props.deep_symbolize_keys
          rows = props[:rows].index_by { |row| row[:id] }
          open_row = rows.fetch(@discrepancy.public_id)
          manual = props.fetch(:manualTrigger)

          assert open_row.dig(:action, :token).present?
          assert Payments::ReconciliationReviewToken.valid?(
            open_row.dig(:action, :token),
            @discrepancy
          )
          assert manual[:allowed]
          assert manual[:ready]
          assert manual[:authorizationUrl].present?
          assert_equal "2025-07-26", manual[:minDate]
          assert_equal "2026-07-25", manual[:maxDate]
          assert_equal "2026-07-25", manual[:defaultDate]
          assert_equal "RECONCILE 2026-07-25 UTC", manual[:confirmation]
          assert Payments::ManualReconciliationToken.valid?(
            manual[:token],
            actor: @admin,
            config: @provider_config,
            date: Date.new(2026, 7, 25)
          )
          [ acknowledged, ignored, resolved ].each do |closed|
            refute rows.fetch(closed.public_id).key?(:action)
          end

          rendered = props.to_json
          assert_includes rendered, "pi_••••1234"
          sensitive_values.each do |secret|
            refute_includes rendered, secret
          end
        end
      end

      test "manual trigger validates the UTC day and suppresses duplicate submissions" do
        travel_to Time.utc(2026, 7, 26, 12) do
          get admin_store_payment_reconciliations_path
          manual = inertia.props.deep_symbolize_keys.fetch(:manualTrigger)

          assert_enqueued_with(job: Payments::DailyReconciliationJob) do
            post manual.fetch(:url),
              params: {
                date: "2026-07-25",
                confirmation: manual.fetch(:confirmation),
                token: manual.fetch(:token)
              }
          end

          assert_redirected_to admin_store_payment_reconciliations_path
          run = Payments::ReconciliationRun.find_by!(
            provider: "stripe",
            mode: "test",
            window_start: Time.utc(2026, 7, 25)
          )
          assert run.pending?
          assert_enqueued_with(
            job: Payments::DailyReconciliationJob,
            args: [
              {
                date: "2026-07-25",
                refresh: false,
                run_id: run.id,
                config_binding:
                  Payments::ReconciliationConfigBinding.generate(
                    config: @provider_config.reload,
                    run: run
                  )
              }
            ]
          )
          assert AuditLog.by_action(
            Payments::RequestManualReconciliation::AUDIT_ACTION
          ).where(
            resource_type: "Payments::ReconciliationRun",
            resource_id: run.id,
            actor_id: @admin.id
          ).exists?

          assert_no_enqueued_jobs do
            replacement_token = Payments::ManualReconciliationToken.issue(
              actor: @admin,
              config: @provider_config.reload,
              date: Date.new(2026, 7, 25)
            )
            post manual.fetch(:url),
              params: {
                date: "2026-07-25",
                confirmation: manual.fetch(:confirmation),
                token: replacement_token
              }
          end

          assert_redirected_to admin_store_payment_reconciliations_path
          assert_equal 1, AuditLog.by_action(
            Payments::RequestManualReconciliation::AUDIT_ACTION
          ).where(
            resource_type: "Payments::ReconciliationRun",
            resource_id: run.id
          ).count
        end
      end

      test "manual authorization issues a date-bound token without caching it" do
        travel_to Time.utc(2026, 7, 26, 12) do
          post manual_authorization_admin_store_payment_reconciliations_path,
            params: { date: "2026-07-24" },
            as: :json

          assert_response :success
          assert_equal "no-store", response.headers["Cache-Control"]
          payload = JSON.parse(response.body)
          assert_equal "RECONCILE 2026-07-24 UTC", payload.fetch("confirmation")
          assert Payments::ManualReconciliationToken.valid?(
            payload.fetch("token"),
            actor: @admin,
            config: @provider_config,
            date: Date.new(2026, 7, 24)
          )
          refute Payments::ManualReconciliationToken.valid?(
            payload.fetch("token"),
            actor: @admin,
            config: @provider_config,
            date: Date.new(2026, 7, 23)
          )
        end
      end

      test "manual trigger rejects a current UTC day and confirmation mismatch" do
        travel_to Time.utc(2026, 7, 26, 12) do
          token = Payments::ManualReconciliationToken.issue(
            actor: @admin,
            config: @provider_config,
            date: Date.new(2026, 7, 26)
          )

          assert_no_enqueued_jobs do
            post trigger_admin_store_payment_reconciliations_path,
              params: {
                date: "2026-07-26",
                confirmation: "RECONCILE 2026-07-26 UTC",
                token: token
              }
          end
          assert_redirected_to admin_store_payment_reconciliations_path

          assert_no_enqueued_jobs do
            post trigger_admin_store_payment_reconciliations_path,
              params: {
                date: "2026-07-25",
                confirmation: "RECONCILE 2026-07-24 UTC",
                token: token
              }
          end
          assert_redirected_to admin_store_payment_reconciliations_path
        end

        refute Payments::ReconciliationRun.exists?(
          provider: "stripe",
          window_start: Time.utc(2026, 7, 25)
        )
      end

      test "successful review records an audit and cannot mutate financial records" do
        payment_before = @payment.attributes.deep_dup
        order_before = @order.attributes.deep_dup
        note = "Verified the mismatch against Stripe and escalated to finance."

        patch review_admin_store_payment_reconciliation_path(@discrepancy),
          params: valid_review_params(
            token: Payments::ReconciliationReviewToken.issue(@discrepancy),
            note: note
          )

        assert_redirected_to admin_store_payment_reconciliations_path
        assert @discrepancy.reload.acknowledged?
        assert_equal @admin.id, @discrepancy.reviewed_by_id
        assert_equal note, @discrepancy.review_note
        assert_equal payment_before, @payment.reload.attributes
        assert_equal order_before, @order.reload.attributes

        audit = AuditLog.find_by!(
          action: "admin.payment_reconciliation_discrepancy_reviewed",
          resource_type: "Payments::ReconciliationDiscrepancy",
          resource_id: @discrepancy.id,
          actor_id: @admin.id
        )
        assert_equal note, audit.reason
        assert_equal({ "status" => "open" }, audit.before_state)
        assert_equal "acknowledged", audit.after_state.fetch("status")
        sensitive_values.each do |secret|
          refute_includes audit.attributes.to_json, secret
        end
      end

      test "failed review leaves status and audit history unchanged" do
        audit_count = AuditLog.where(
          action: "admin.payment_reconciliation_discrepancy_reviewed",
          resource_type: "Payments::ReconciliationDiscrepancy",
          resource_id: @discrepancy.id
        ).count
        state_before = @discrepancy.attributes.deep_dup

        patch review_admin_store_payment_reconciliation_path(@discrepancy),
          params: valid_review_params(token: "invalid-review-token")

        assert_redirected_to admin_store_payment_reconciliations_path
        assert_equal state_before, @discrepancy.reload.attributes
        assert_equal audit_count, AuditLog.where(
          action: "admin.payment_reconciliation_discrepancy_reviewed",
          resource_type: "Payments::ReconciliationDiscrepancy",
          resource_id: @discrepancy.id
        ).count
      end

      test "serializer and query expose no stored provider cursors references or lease tokens" do
        serialized = Payments::ReconciliationSerializer.discrepancy(
          @discrepancy
        )
        run_payload = Payments::ReconciliationSerializer.run(@run)
        rendered = { discrepancy: serialized, run: run_payload }.to_json

        assert_equal "pi_••••1234", serialized[:reference]
        assert_equal @discrepancy.public_id, serialized[:id]
        %i[
          reference_digest
          fingerprint
          payment_cursor
          refund_cursor
          processing_token
        ].each do |forbidden_key|
          refute serialized.key?(forbidden_key)
          refute run_payload.key?(forbidden_key)
        end
        sensitive_values.each do |secret|
          refute_includes rendered, secret
          assert_empty Payments::ReconciliationDiscrepanciesQuery.new(
            query: secret
          ).relation
        end
        assert_equal [ @discrepancy.id ],
          Payments::ReconciliationDiscrepanciesQuery.new(
            query: @discrepancy.public_id
          ).relation.pluck(:id)
      end

      private

      def configure_stripe!
        config = Payments::ProviderConfig.find_or_initialize_by(
          provider: "stripe"
        )
        config.assign_attributes(
          enabled: true,
          mode: "test",
          credentials: {
            "secret_key" => "sk_test_admin_reconciliation",
            "webhook_secret" => "whsec_admin_reconciliation"
          }
        )
        config.save!
        mark_stripe_provider_connection_tested!(config, actor: @admin)
      end

      def create_run
        Payments::ReconciliationRun.create!(
          provider: "stripe",
          mode: "test",
          window_start: Time.utc(2026, 7, 20),
          window_end: Time.utc(2026, 7, 21),
          status: "running",
          phase: "payments",
          payment_cursor: PAYMENT_CURSOR,
          refund_cursor: REFUND_CURSOR,
          processing_token: PROCESSING_TOKEN,
          attempt_count: 1,
          refresh_count: 1,
          started_at: Time.current,
          last_heartbeat_at: Time.current
        )
      end

      def create_payment
        customer = create_user(email: "reconciliation-private@example.com")
        order = Commerce::Order.create!(
          public_id: "ord_reconciliation_#{SecureRandom.hex(6)}",
          order_number: "RECON-ADMIN-#{SecureRandom.hex(5).upcase}",
          user: customer,
          status: "paid",
          subtotal_cents: 2_500,
          discount_cents: 0,
          total_cents: 2_500,
          currency: "CNY"
        )
        payment = Payments::Record.create!(
          order: order,
          provider: "stripe",
          status: "succeeded",
          amount_cents: 2_500,
          currency: "CNY",
          provider_payment_id: PAYMENT_REFERENCE,
          metadata: {
            "stripe_payment_intent_id" => PAYMENT_REFERENCE,
            "customer_email" => customer.email
          }
        )

        [ order, payment ]
      end

      def create_discrepancy(run:, status: "open", suffix: SecureRandom.hex(4),
                             payment_record: nil, order: nil)
        attributes = {
          run: run,
          provider: "stripe",
          mode: "test",
          subject_type: "payment",
          kind: "payment_amount_mismatch",
          reference_masked: "pi_••••1234",
          reference_digest: Digest::SHA256.hexdigest("reference-#{suffix}"),
          fingerprint: Digest::SHA256.hexdigest("fingerprint-#{suffix}"),
          status: status,
          payment_record: payment_record,
          order: order,
          local_status: payment_record&.status,
          provider_status: "succeeded",
          local_amount_cents: payment_record&.amount_cents || 2_500,
          provider_amount_cents: 2_600,
          local_currency: "CNY",
          provider_currency: "CNY",
          first_seen_at: 2.hours.ago,
          last_seen_at: 1.hour.ago
        }
        if status.in?(%w[acknowledged ignored])
          attributes.merge!(
            reviewed_by: @admin,
            reviewed_at: 30.minutes.ago,
            review_note: "Reviewed reconciliation discrepancy."
          )
        elsif status == "resolved"
          attributes[:resolved_at] = 30.minutes.ago
        end

        Payments::ReconciliationDiscrepancy.create!(attributes)
      end

      def valid_review_params(token:, note: "Verified against Stripe before review.")
        {
          token: token,
          confirmation: @discrepancy.public_id,
          decision: "acknowledge",
          note: note
        }
      end

      def sensitive_values
        [
          PAYMENT_REFERENCE,
          PAYMENT_CURSOR,
          REFUND_CURSOR,
          PROCESSING_TOKEN,
          "reconciliation-private@example.com"
        ]
      end
    end
  end
end
