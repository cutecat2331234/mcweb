# frozen_string_literal: true

require "test_helper"

module Commerce
  class FulfillmentRecoveryTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      grant_permission(@actor, "store.fulfillments.retry")
      grant_permission(@actor, "store.fulfillments.cancel")
      @customer = create_user
      @order = Commerce::Order.create!(
        user: @customer,
        status: "fulfilling",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      @item = Commerce::OrderItem.create!(
        order: @order,
        product_name: "Recovery item",
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {
          fulfillment_config: {
            commands: [ "say delivered" ],
            server_id: "missing-recovery-server"
          }
        }
      )
      @fulfillment = Commerce::Fulfillment.create!(
        order: @order,
        order_item: @item,
        status: "failed",
        attempts_count: 1,
        last_error: "timeout"
      )
      @reason = "Verified payment, inventory, and the target connector state."
      @request_id = SecureRandom.uuid
    end

    test "signed retry supersedes active work, audits, enqueues, and replays once" do
      task = connector_task(status: "pending")
      authorization = authorize("retry")
      assert authorization.success?, authorization.error.inspect

      assert_enqueued_with(job: Minecraft::EnsureInstanceRunningJob, args: [ @fulfillment.id ]) do
        result = execute("retry", authorization.value)
        assert result.success?
        refute result.value.fetch(:idempotent)
      end
      replay = execute("retry", authorization.value)

      assert replay.success?
      assert replay.value.fetch(:idempotent)
      assert_equal "pending", @fulfillment.reload.status
      assert_equal "failed", task.reload.status
      assert_equal "superseded_by_manual_retry", task.result["error"]
      assert_equal 1, @fulfillment.attempts.where(action: "retry").count
      assert AuditLog.exists?(
        action: "commerce.fulfillment_retry",
        resource_type: "Commerce::Fulfillment",
        resource_id: @fulfillment.id,
        request_id: @request_id
      )
    end

    test "state changes invalidate a signed preview" do
      authorization = authorize("retry")
      @fulfillment.update!(attempts_count: 2)

      result = execute("retry", authorization.value)

      assert result.failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_authorization_invalid"), result.error
      assert_equal "failed", @fulfillment.reload.status
      refute @fulfillment.attempts.exists?(request_id: @request_id)
    end

    test "signed cancellation stops active tasks and records a reason" do
      task = connector_task(status: "claimed")
      authorization = authorize("cancel")

      result = execute("cancel", authorization.value)

      assert result.success?
      assert_equal "cancelled", @fulfillment.reload.status
      assert_equal @reason, @fulfillment.cancel_reason
      assert_equal "failed", task.reload.status
      assert_equal "fulfillment_cancelled", task.result["error"]
      assert AuditLog.exists?(
        action: "commerce.fulfillment_cancel",
        resource_type: "Commerce::Fulfillment",
        resource_id: @fulfillment.id,
        request_id: @request_id
      )
    end

    test "authorization and audit failures never change fulfillment state" do
      denied = Commerce::ManualFulfillmentAction.call(
        actor: create_user,
        fulfillment: @fulfillment,
        action: "retry",
        request_id: SecureRandom.uuid,
        reason: @reason,
        authorize_only: true
      )
      assert denied.failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), denied.error

      authorization = authorize("cancel")
      assert_raises ActiveRecord::StatementInvalid do
        Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          execute("cancel", authorization.value)
        end
      end
      assert_equal "failed", @fulfillment.reload.status
      refute @fulfillment.attempts.exists?(request_id: @request_id)
    end

    test "automatic dispatch records a safe attempt and terminal result" do
      server = Minecraft::Server.create!(
        public_id: "srv-recovery-#{SecureRandom.hex(4)}",
        name: "Recovery server",
        connector_secret: SecureRandom.hex(16)
      )
      @item.update!(
        fulfillment_snapshot: {
          fulfillment_config: {
            commands: [ "say delivered" ],
            server_id: server.public_id
          }
        }
      )
      @fulfillment.update!(status: "pending", attempts_count: 0, last_error: nil)

      Minecraft::DispatchFulfillmentJob.perform_now(@fulfillment.id)

      attempt = @fulfillment.attempts.dispatches.last
      assert_equal "processing", @fulfillment.reload.status
      assert_equal 1, @fulfillment.attempts_count
      assert_equal "processing", attempt.status

      task = @fulfillment.connector_tasks.first
      result = Minecraft::TaskDispatcher.call(
        server: server,
        task: task,
        result: { success: true, status: "completed", secret: "must-not-persist" },
        action: :complete
      )

      assert result.success?
      assert_equal "fulfilled", @fulfillment.reload.status
      assert_equal "succeeded", attempt.reload.status
      refute_includes attempt.result_summary.keys, "secret"
      refute_includes @fulfillment.last_result_summary.keys, "secret"
    end

    test "recovery job requeues due failures and exhausts interrupted work safely" do
      @fulfillment.update!(next_attempt_at: 1.minute.ago)
      assert_enqueued_with(job: Minecraft::EnsureInstanceRunningJob, args: [ @fulfillment.id ]) do
        Commerce::RecoverFulfillmentsJob.perform_now
      end
      assert_equal "pending", @fulfillment.reload.status

      @fulfillment.update!(
        status: "processing",
        attempts_count: @fulfillment.max_attempts,
        updated_at: 1.hour.ago
      )
      attempt = @fulfillment.attempts.create!(
        attempt_number: @fulfillment.max_attempts,
        idempotency_key: "interrupted-#{SecureRandom.uuid}",
        trigger: "automatic",
        action: "dispatch",
        status: "processing",
        started_at: 1.hour.ago
      )

      assert_no_enqueued_jobs(only: Minecraft::EnsureInstanceRunningJob) do
        Commerce::RecoverFulfillmentsJob.perform_now
      end

      assert_equal "failed", @fulfillment.reload.status
      assert @fulfillment.exhausted?
      assert_nil @fulfillment.next_attempt_at
      assert_equal "worker_interrupted", attempt.reload.error_code
    end

    private

    def authorize(action)
      Commerce::ManualFulfillmentAction.call(
        actor: @actor,
        fulfillment: @fulfillment,
        action: action,
        request_id: @request_id,
        reason: @reason,
        authorize_only: true
      )
    end

    def execute(action, authorization)
      Commerce::ManualFulfillmentAction.call(
        actor: @actor,
        fulfillment: @fulfillment,
        action: action,
        request_id: @request_id,
        reason: @reason,
        authorization_token: authorization.fetch(:authorization_token),
        confirmation: authorization.fetch(:confirmation)
      )
    end

    def connector_task(status:)
      server = Minecraft::Server.create!(
        public_id: "srv-task-#{SecureRandom.hex(4)}",
        name: "Task server",
        connector_secret: SecureRandom.hex(16)
      )
      Minecraft::ConnectorTask.create!(
        server: server,
        fulfillment: @fulfillment,
        task_type: "deliver_item",
        delivery_id: @fulfillment.delivery_id,
        status: status,
        payload: {}
      )
    end
  end
end
