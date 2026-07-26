# frozen_string_literal: true

require "test_helper"

class Payments::WebhookReliabilityTest < ActiveSupport::TestCase
  setup do
    clear_enqueued_jobs
  end

  test "rejects reuse of a provider event id with a different signed payload" do
    first = receive_fake_webhook(event_id: "evt_digest_reuse", payment_id: "fake_one")
    second = receive_fake_webhook(event_id: "evt_digest_reuse", payment_id: "fake_two")

    assert first.success?
    assert second.failure?
    assert_equal "event_payload_mismatch", second.code
    assert_equal "fake_one", first.value.fetch(:event).reload.payload.fetch("payment_id")
  end

  test "moves retryable failures to dead letter after the bounded retry cycle" do
    received = receive_fake_webhook(
      event_id: "evt_retry_cycle",
      payment_id: "missing_payment"
    )
    event = received.value.fetch(:event)

    4.times do
      result = Payments::ProcessStoredWebhook.call(event: event, source: "automatic")
      assert result.failure?
      assert event.reload.failed?
      assert event.next_retry_at.present?
    end

    final = Payments::ProcessStoredWebhook.call(event: event, source: "automatic")

    assert final.failure?
    assert event.reload.dead_letter?
    assert_equal 5, event.retry_count
    assert_equal 5, event.attempt_count
    assert event.dead_lettered_at.present?
    assert_nil event.next_retry_at
  end

  test "quarantines a stored payload that no longer matches its verified digest" do
    received = receive_fake_webhook(
      event_id: "evt_tampered_payload",
      payment_id: "missing_payment"
    )
    event = received.value.fetch(:event)
    event.update_column(:payload, { "payment_id" => "tampered" })

    result = Payments::ProcessStoredWebhook.call(event: event)

    assert result.failure?
    assert_equal "payload_integrity_failure", result.code
    assert event.reload.dead_letter?
    assert_equal "payload_integrity_failure", event.last_error_code
  end

  test "manual replay requires permission reason and a fresh event-bound token" do
    actor = create_user
    grant_permission(actor, Payments::ReplayWebhookEvent::PERMISSION)
    event = dead_letter_event("evt_manual_replay")
    stale_token = Payments::WebhookReplayToken.issue(event)
    event.touch

    rejected = Payments::ReplayWebhookEvent.call(
      event: event,
      actor: actor,
      token: stale_token,
      reason: "Investigating a verified payment event"
    )
    assert rejected.failure?
    assert_equal "invalid_replay_token", rejected.code

    fresh_token = Payments::WebhookReplayToken.issue(event.reload)
    assert_enqueued_jobs 1 do
      accepted = Payments::ReplayWebhookEvent.call(
        event: event,
        actor: actor,
        token: fresh_token,
        reason: "Reprocess after payment record recovery"
      )
      assert accepted.success?
    end

    assert event.reload.received?
    assert_equal 1, event.manual_replay_count
    assert_equal actor, event.last_replayed_by
  end

  test "recovery job enqueues verified received events that were not dispatched" do
    event = receive_fake_webhook(
      event_id: "evt_recover_received",
      payment_id: "missing_payment"
    ).value.fetch(:event)
    event.update_column(
      :updated_at,
      Payments::ReceiveWebhook::RECEIVED_RECLAIM_AFTER.ago - 1.second
    )

    assert_enqueued_jobs 1, only: Payments::ProcessWebhookJob do
      Payments::RecoverWebhookEventsJob.perform_now
    end
  end

  private

  def receive_fake_webhook(event_id:, payment_id:)
    payload = { payment_id: payment_id }.to_json
    Payments::ReceiveWebhook.call(
      provider: "fake",
      event_id: event_id,
      event_type: "payment.succeeded",
      payload: payload,
      signature: OpenSSL::HMAC.hexdigest(
        "SHA256",
        "fake_webhook_secret",
        payload
      )
    )
  end

  def dead_letter_event(event_id)
    event = receive_fake_webhook(
      event_id: event_id,
      payment_id: "missing_payment"
    ).value.fetch(:event)
    event.update!(
      status: "dead_letter",
      dead_lettered_at: Time.current,
      processed_at: Time.current,
      last_error_code: "payment_not_found"
    )
    event
  end
end
