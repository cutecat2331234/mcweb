# frozen_string_literal: true

module Payments
  class ReplayWebhookEvent < ApplicationService
    PERMISSION = "store.payments.replay"
    MIN_REASON_LENGTH = 10
    MAX_REASON_LENGTH = 500

    def initialize(event:, actor:, token:, reason:)
      @event = event
      @actor = actor
      @token = token
      @reason = reason.to_s.strip
    end

    def call
      return forbidden_result unless @actor&.permission?(PERMISSION)
      return invalid_reason_result unless valid_reason?

      replay_event = nil

      Payments::WebhookEvent.transaction do
        event = Payments::WebhookEvent.lock.find(@event.id)

        unless Payments::WebhookReplayToken.valid?(@token, event)
          return ServiceResult.failure(
            error: "Webhook replay authorization expired or is invalid.",
            code: "invalid_replay_token"
          )
        end

        unless event.manually_replayable?
          return ServiceResult.failure(
            error: "This webhook event is not eligible for manual replay.",
            code: "webhook_not_replayable"
          )
        end

        previous_status = event.status
        event.update!(
          status: :received,
          retry_count: 0,
          manual_replay_count: event.manual_replay_count + 1,
          last_replayed_at: Time.current,
          last_replayed_by: @actor,
          processing_started_at: nil,
          processing_token: nil,
          next_retry_at: nil,
          dead_lettered_at: nil,
          processed_at: nil,
          error_message: nil,
          last_error_code: nil
        )

        Administration::AuditLogger.call(
          actor: @actor,
          action: "admin.payment_webhook_replay_requested",
          resource: event,
          reason: @reason,
          metadata: {
            provider: event.provider,
            previous_status: previous_status,
            attempt_count: event.attempt_count,
            manual_replay_count: event.manual_replay_count
          }
        )
        replay_event = event
      end

      Payments::ProcessWebhookJob.perform_later(
        webhook_event_id: replay_event.id,
        source: "manual",
        actor_id: @actor.id
      )

      ServiceResult.success(event: replay_event)
    end

    private

    def valid_reason?
      @reason.length.between?(MIN_REASON_LENGTH, MAX_REASON_LENGTH)
    end

    def invalid_reason_result
      ServiceResult.failure(
        error: "A replay reason between #{MIN_REASON_LENGTH} and #{MAX_REASON_LENGTH} characters is required.",
        code: "invalid_replay_reason"
      )
    end

    def forbidden_result
      ServiceResult.failure(
        error: "You do not have permission to replay payment webhooks.",
        code: "forbidden"
      )
    end
  end
end
