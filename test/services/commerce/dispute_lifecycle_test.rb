# frozen_string_literal: true

require "test_helper"

module Commerce
  class DisputeLifecycleTest < ActiveSupport::TestCase
    setup do
      @actor = create_user
      %w[
        store.disputes.read
        store.disputes.sensitive_read
        store.disputes.assign
        store.disputes.note
        store.disputes.evidence_submit
        store.disputes.accept_loss
        store.disputes.close
        store.disputes.rights_manage
      ].each { |permission| grant_permission(@actor, permission) }

      @customer = create_user
      @order = Commerce::Order.create!(
        user: @customer,
        status: "completed",
        currency: "CNY",
        subtotal_cents: 1_000,
        total_cents: 1_000
      )
      @product = Commerce::Product.create!(
        name: "Dispute entitlement",
        slug: "dispute-entitlement-#{SecureRandom.hex(4)}",
        product_type: "digital",
        status: "active",
        price_cents: 1_000,
        currency: "CNY"
      )
      @item = Commerce::OrderItem.create!(
        order: @order,
        product: @product,
        product_name: @product.name,
        unit_price_cents: 1_000,
        quantity: 1,
        total_cents: 1_000,
        fulfillment_snapshot: {}
      )
      @entitlement = Commerce::UserEntitlement.create!(
        user: @customer,
        product: @product,
        source_order_item: @item,
        starts_at: 1.day.ago
      )
      @payment = Payments::Record.create!(
        order: @order,
        provider: "fake",
        provider_payment_id: "fake_dispute_#{SecureRandom.hex(8)}",
        status: "succeeded",
        amount_cents: 1_000,
        currency: "CNY"
      )
      @occurred_at = Time.current.change(usec: 0)
      @evidence_due_at = @occurred_at + 2.days
    end

    test "channel replay and stale events preserve state while terminal recovery restores rights" do
      opened = apply_channel(
        event_id: "evt-open",
        dispute_id: "dp-main",
        status: "needs_response",
        amount_cents: 600,
        sequence: 200
      )

      assert_predicate opened, :success?, opened.error
      dispute = opened.value.fetch(:dispute)
      assert_equal "evidence_required", dispute.status
      assert_equal 600, dispute.liability_cents
      assert_equal 0, dispute.offset_cents
      assert_equal "frozen", dispute.rights_status
      assert_not @entitlement.reload.currently_active?
      assert_equal 1, dispute.events.count
      assert_equal 1, dispute.rights_actions.count

      replay = apply_channel(
        event_id: "evt-open",
        dispute_id: "dp-main",
        status: "needs_response",
        amount_cents: 600,
        sequence: 200
      )
      assert_predicate replay, :success?
      assert replay.value.fetch(:idempotent)
      assert_equal 1, dispute.events.count
      assert_equal 1, dispute.rights_actions.count

      stale = apply_channel(
        event_id: "evt-stale",
        dispute_id: "dp-main",
        status: "lost",
        amount_cents: 600,
        sequence: 100,
        occurred_at: @occurred_at - 1.minute
      )
      assert_predicate stale, :success?
      assert stale.value.fetch(:stale)
      assert_equal "evidence_required", dispute.reload.status
      assert_equal true, dispute.events.find_by!(provider_event_id: "evt-stale").metadata["stale"]

      won = apply_channel(
        event_id: "evt-won",
        dispute_id: "dp-main",
        status: "won",
        amount_cents: 600,
        sequence: 300,
        occurred_at: @occurred_at + 1.minute
      )
      assert_predicate won, :success?, won.error
      assert_equal "won", dispute.reload.status
      assert_equal 0, dispute.liability_cents
      assert_equal 600, dispute.offset_cents
      assert_equal "restored", dispute.rights_status
      assert @entitlement.reload.currently_active?
      assert_equal dispute.amount_cents,
                   dispute.liability_cents + dispute.offset_cents
      assert_equal 3, dispute.events.where(source: "channel").count
      assert_equal 3, AuditLog.where(
        resource_type: "Commerce::Dispute",
        resource_id: dispute.id
      )
        .where(action: %w[
          commerce.dispute_channel_event_applied
          commerce.dispute_channel_event_ignored
        ]).count
    end

    test "partial refunds rebalance gross dispute exposure without double restoration" do
      dispute = apply_channel(
        event_id: "evt-partial",
        dispute_id: "dp-partial",
        status: "under_review",
        amount_cents: 700,
        sequence: 10
      ).value.fetch(:dispute)

      refund = Commerce::Refund.create!(
        order: @order,
        payment_record: @payment,
        status: "completed",
        restoration_status: "completed",
        amount_cents: 500,
        provider_refund_id: "fake_refund_partial"
      )
      result = Commerce::Disputes::RebalanceExposure.call(
        payment_record: @payment,
        trigger_idempotency: "refund:#{refund.id}:test"
      )

      assert_predicate result, :success?, result.error
      assert_equal 500, dispute.reload.liability_cents
      assert_equal 200, dispute.offset_cents
      assert_equal @payment.amount_cents,
                   refund.amount_cents + dispute.liability_cents
      assert_equal dispute.amount_cents,
                   dispute.liability_cents + dispute.offset_cents

      replay = Commerce::Disputes::RebalanceExposure.call(
        payment_record: @payment,
        trigger_idempotency: "refund:#{refund.id}:test"
      )
      assert_predicate replay, :success?
      assert_equal 1, dispute.events.where(event_type: "exposure_rebalanced").count
    end

    test "signed actions reject changed previews and replay accepted loss once" do
      dispute = apply_channel(
        event_id: "evt-action",
        dispute_id: "dp-action",
        status: "needs_response",
        amount_cents: 800,
        sequence: 10
      ).value.fetch(:dispute)
      request_id = SecureRandom.uuid
      authorization = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        authorize_only: true
      )
      assert_predicate authorization, :success?, authorization.error
      preview_lock = dispute.reload.lock_version

      apply_channel(
        event_id: "evt-action-review",
        dispute_id: "dp-action",
        status: "under_review",
        amount_cents: 800,
        sequence: 20,
        occurred_at: @occurred_at + 1.minute
      )
      changed = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        expected_lock_version: preview_lock,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      )
      assert_predicate changed, :failure?
      assert_equal I18n.t("mcweb.services.errors.dispute_state_changed"), changed.error

      request_id = SecureRandom.uuid
      authorization = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        authorize_only: true
      )
      accepted = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        expected_lock_version: dispute.reload.lock_version,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      )
      replay = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        expected_lock_version: dispute.reload.lock_version,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      )

      assert_predicate accepted, :success?, accepted.error
      assert_predicate replay, :success?, replay.error
      assert replay.value.fetch(:idempotent)
      assert_equal "lost", dispute.reload.status
      assert_equal "accepted_loss", dispute.resolution
      assert_equal "revoked", dispute.rights_status
      assert_equal 1, dispute.events.where(request_id: request_id).count
      assert_equal 1, AuditLog.where(
        resource_type: "Commerce::Dispute",
        resource_id: dispute.id,
        action: "commerce.dispute_accept_loss",
        request_id: request_id
      ).count
    end

    test "permission and audit failures roll back every dispute mutation" do
      dispute = apply_channel(
        event_id: "evt-denied",
        dispute_id: "dp-denied",
        status: "needs_response",
        amount_cents: 400,
        sequence: 10
      ).value.fetch(:dispute)
      denied = Commerce::Disputes::ExecuteAction.call(
        actor: create_user,
        dispute: dispute,
        action: "assign",
        request_id: SecureRandom.uuid,
        reason: "Reviewed ownership.",
        assignee_id: @actor.id
      )
      assert_predicate denied, :failure?
      assert_nil dispute.reload.assigned_to_id

      request_id = SecureRandom.uuid
      assert_raises ActiveRecord::StatementInvalid do
        Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          action(
            dispute,
            "assign",
            request_id: request_id,
            assignee_id: @actor.id
          )
        end
      end
      assert_nil dispute.reload.assigned_to_id
      refute dispute.events.exists?(request_id: request_id)
    end

    test "dangerous execution denies a stale actor after permission revocation" do
      dispute = apply_channel(
        event_id: "evt-revoked-action",
        dispute_id: "dp-revoked-action",
        status: "needs_response",
        amount_cents: 400,
        sequence: 10
      ).value.fetch(:dispute)
      request_id = SecureRandom.uuid
      authorization = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        authorize_only: true
      )
      permission = Permission.find_by!(key: "store.disputes.accept_loss")
      role = @actor.roles.joins(:permissions).find_by!(permissions: { id: permission.id })
      assert @actor.permission?(permission.key)
      role.revoke_permission!(permission)

      result = action(
        dispute,
        "accept_loss",
        request_id: request_id,
        authorization_token: authorization.value[:authorization_token],
        confirmation: authorization.value[:confirmation]
      )

      assert_predicate result, :failure?
      assert_equal I18n.t("mcweb.services.errors.high_risk_unauthorized"), result.error
      assert_equal "evidence_required", dispute.reload.status
      refute dispute.events.exists?(request_id: request_id)
    end

    test "evidence download expires and retention purge is blocked until closed period ends" do
      dispute = apply_channel(
        event_id: "evt-evidence",
        dispute_id: "dp-evidence",
        status: "needs_response",
        amount_cents: 300,
        sequence: 10
      ).value.fetch(:dispute)
      submitted = action(
        dispute,
        "submit_evidence",
        request_id: SecureRandom.uuid,
        evidence: {
          title: "Delivery proof",
          filename: "delivery-proof.txt",
          content_type: "text/plain",
          content: "Immutable delivery proof"
        }
      )
      assert_predicate submitted, :success?, submitted.error
      evidence = submitted.value.fetch(:evidence)

      token = Commerce::Disputes::EvidenceDownloadToken.issue(
        evidence: evidence,
        actor: @actor
      )
      assert_predicate token, :success?
      assert Commerce::Disputes::EvidenceDownloadToken.valid?(
        token.value[:token],
        evidence: evidence,
        actor: @actor
      )
      travel 6.minutes do
        refute Commerce::Disputes::EvidenceDownloadToken.valid?(
          token.value[:token],
          evidence: evidence,
          actor: @actor
        )
      end

      blocked = Commerce::Disputes::PurgeEvidence.call(
        evidence: evidence,
        at: 10.years.from_now
      )
      assert_predicate blocked, :failure?
      assert_equal "Immutable delivery proof", evidence.reload.content

      apply_channel(
        event_id: "evt-evidence-won",
        dispute_id: "dp-evidence",
        status: "won",
        amount_cents: 300,
        sequence: 20,
        occurred_at: @occurred_at + 1.minute
      )
      closed = action(
        dispute,
        "close",
        request_id: SecureRandom.uuid
      )
      assert_predicate closed, :success?, closed.error
      assert dispute.reload.retention_until.present?
      assert_equal dispute.retention_until, evidence.reload.retention_until

      purged = Commerce::Disputes::PurgeEvidence.call(
        evidence: evidence,
        at: dispute.retention_until + 1.second
      )
      assert_predicate purged, :success?, purged.error
      assert evidence.reload.purged?
      assert_nil evidence.content
      assert AuditLog.exists?(
        resource_type: "Commerce::Dispute",
        resource_id: dispute.id,
        action: "commerce.dispute_evidence_purged"
      )
    end

    test "stored webhook replay creates one dispute event" do
      payload = {
        payment_id: @payment.provider_payment_id,
        dispute_id: "dp-webhook",
        status: "needs_response",
        amount: 250,
        currency: "CNY",
        occurred_at: @occurred_at.iso8601,
        sequence: 10,
        evidence_due_at: 2.days.from_now.iso8601,
        risk_level: "high",
        reason: "unrecognized"
      }
      body = payload.to_json
      signature = OpenSSL::HMAC.hexdigest("SHA256", "fake_webhook_secret", body)
      arguments = {
        provider: "fake",
        event_id: "evt-webhook-replay",
        event_type: "dispute.created",
        payload: body,
        signature: signature
      }

      first = Payments::WebhookProcessor.call(**arguments)
      second = Payments::WebhookProcessor.call(**arguments)

      assert_predicate first, :success?, first.error
      assert_predicate second, :success?, second.error
      assert second.value.fetch(:idempotent)
      dispute = Commerce::Dispute.find_by!(provider_dispute_id: "dp-webhook")
      assert_equal 1, dispute.events.where(provider_event_id: "evt-webhook-replay").count
      assert_equal 1, Payments::WebhookEvent.where(event_id: "evt-webhook-replay").count
    end

    private

    def apply_channel(
      event_id:,
      dispute_id:,
      status:,
      amount_cents:,
      sequence:,
      occurred_at: @occurred_at
    )
      Commerce::Disputes::ApplyChannelEvent.call(
        provider: "fake",
        provider_event_id: event_id,
        provider_dispute_id: dispute_id,
        payment_record: @payment,
        event_type: "dispute.updated",
        provider_status: status,
        amount_cents: amount_cents,
        currency: "CNY",
        occurred_at: occurred_at,
        sequence: sequence,
        evidence_due_at: @evidence_due_at,
        risk_level: "high",
        reason_code: "unrecognized",
        kind: "dispute"
      )
    end

    def action(
      dispute,
      name,
      request_id:,
      expected_lock_version: dispute.reload.lock_version,
      assignee_id: nil,
      evidence: {},
      authorization_token: nil,
      confirmation: nil,
      authorize_only: false
    )
      Commerce::Disputes::ExecuteAction.call(
        actor: @actor,
        dispute: dispute,
        action: name,
        request_id: request_id,
        reason: "Verified the order, payment, refund, and current rights state.",
        expected_lock_version: expected_lock_version,
        assignee_id: assignee_id,
        evidence: evidence,
        authorization_token: authorization_token,
        confirmation: confirmation,
        authorize_only: authorize_only
      )
    end
  end
end
