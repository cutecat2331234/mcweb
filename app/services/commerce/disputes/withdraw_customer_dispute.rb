# frozen_string_literal: true

module Commerce
  module Disputes
    class WithdrawCustomerDispute < ApplicationService
      MAX_REASON_LENGTH = 500

      def initialize(
        order:,
        dispute:,
        actor:,
        request_id:,
        reason: nil,
        ip_address: nil,
        user_agent: nil,
        now: Time.current
      )
        @order = order
        @dispute = dispute
        @actor = actor
        @request_id = Commerce::HighRiskActionAuthorization.normalize_request_id(request_id)
        @reason = reason.to_s.strip
        @ip_address = ip_address
        @user_agent = user_agent
        @now = now
      end

      def call
        return failure("customer_dispute_request_id_invalid") unless @request_id
        return failure("customer_dispute_withdraw_reason_too_long") if @reason.length > MAX_REASON_LENGTH
        unless CustomerPolicy.order_owned_by?(order: @order, actor: @actor) &&
            @dispute&.store_order_id == @order.id
          return failure("customer_dispute_unavailable")
        end

        existing = existing_event
        return idempotency_result(existing) if existing

        result = nil
        Commerce::Dispute.transaction do
          order, _payment, dispute = Commerce::FinancialLocking.lock_order_payment_dispute!(
            order_id: @order.id,
            payment_record_id: @dispute.payment_record_id,
            dispute_id: @dispute.id
          )
          @dispute = dispute

          unless CustomerPolicy.order_owned_by?(order:, actor: @actor)
            result = failure("customer_dispute_unavailable")
            next
          end

          existing = existing_event
          if existing
            result = idempotency_result(existing)
            next
          end

          unless dispute.customer_withdrawable_by?(@actor)
            result = failure("customer_dispute_withdraw_unavailable")
            next
          end

          before = audit_state(dispute)
          dispute.update!(
            status: "withdrawn",
            resolution: "withdrawn",
            provider_status: "customer_withdrawn",
            liability_cents: 0,
            offset_cents: dispute.amount_cents,
            customer_withdrawn_at: @now,
            retention_until: [
              dispute.retention_until,
              @now + Commerce::Dispute::RETENTION_PERIOD
            ].compact.max
          )

          restore_rights!(dispute) if dispute.rights_frozen? || dispute.rights_revoked?

          event = Commerce::DisputeEvent.create!(
            dispute:,
            actor: @actor,
            idempotency_key: event_idempotency_key,
            request_id: @request_id,
            source: "manual",
            event_type: "customer_withdrawn",
            from_status: before.fetch(:status),
            to_status: dispute.status,
            note: @reason.presence,
            payload_digest: request_fingerprint,
            metadata: {
              "request_fingerprint" => request_fingerprint,
              "released_liability_cents" => before.fetch(:liability_cents)
            }
          )
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.customer_dispute_withdrawn",
            resource: dispute,
            request_id: @request_id,
            reason: @reason.presence || "customer_withdrawal",
            before_state: before,
            after_state: audit_state(dispute),
            metadata: {
              dispute_event_id: event.id,
              order_public_id: order.public_id
            },
            ip_address: @ip_address,
            user_agent: @user_agent
          )
          notification = Commerce::Disputes::CustomerNotifier.call(event:)
          ensure_success!(dispute, notification, "customer_dispute_notification_failed")

          result = ServiceResult.success(dispute:, event:, idempotent: false)
        end

        result
      rescue Commerce::FinancialLocking::BindingMismatch
        failure("customer_dispute_payment_binding_mismatch")
      rescue ActiveRecord::RecordNotUnique
        idempotency_result(existing_event) || failure("customer_dispute_withdraw_unavailable")
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def restore_rights!(dispute)
        result = Commerce::Disputes::RightsPolicy.call(
          dispute:,
          action: "restore",
          idempotency_prefix: event_idempotency_key,
          actor: @actor,
          reason: @reason.presence || "customer_payment_dispute_withdrawn"
        )
        ensure_success!(dispute, result, "customer_dispute_rights_failed")
      end

      def existing_event
        Commerce::DisputeEvent.find_by(idempotency_key: event_idempotency_key)
      end

      def idempotency_result(event)
        return unless event
        unless event.event_type == "customer_withdrawn" &&
            event.actor_id == @actor.id &&
            secure_match?(event.metadata["request_fingerprint"], request_fingerprint)
          return failure("customer_dispute_idempotency_conflict")
        end

        ServiceResult.success(dispute: event.dispute, event:, idempotent: true)
      end

      def request_fingerprint
        @request_fingerprint ||= Digest::SHA256.hexdigest(
          JSON.generate(
            actor_id: @actor&.id,
            order_id: @order&.id,
            dispute_id: @dispute&.id,
            action: "customer_dispute_withdraw",
            request_id: @request_id,
            reason: @reason
          )
        )
      end

      def event_idempotency_key
        "dispute-customer-withdraw:#{@actor&.id}:#{@request_id}"
      end

      def audit_state(dispute)
        {
          status: dispute.status,
          resolution: dispute.resolution,
          liability_cents: dispute.liability_cents,
          offset_cents: dispute.offset_cents,
          rights_status: dispute.rights_status,
          customer_withdrawn_at: dispute.customer_withdrawn_at&.iso8601(6)
        }
      end

      def ensure_success!(dispute, service_result, fallback)
        return if service_result.success?

        dispute.errors.add(:base, service_result.error.presence || fallback)
        raise ActiveRecord::RecordInvalid.new(dispute)
      end

      def failure(code)
        ServiceResult.failure(error: code, code:)
      end

      def secure_match?(left, right)
        left = left.to_s
        right = right.to_s
        left.bytesize == right.bytesize &&
          ActiveSupport::SecurityUtils.secure_compare(left, right)
      end
    end
  end
end
