# frozen_string_literal: true

module Commerce
  module Disputes
    class CreateCustomerDispute < ApplicationService
      REASON_KINDS = %w[
        unauthorized duplicate incorrect_amount product_not_received other
      ].freeze
      MIN_DESCRIPTION_LENGTH = 10
      MAX_DESCRIPTION_LENGTH = 2_000

      def initialize(
        order:,
        actor:,
        request_id:,
        reason_kind:,
        description:,
        amount_cents: nil,
        ip_address: nil,
        user_agent: nil,
        now: Time.current
      )
        @order = order
        @actor = actor
        @request_id = Commerce::HighRiskActionAuthorization.normalize_request_id(request_id)
        @reason_kind = reason_kind.to_s
        @description = description.to_s.strip
        @amount_cents = amount_cents
        @ip_address = ip_address
        @user_agent = user_agent
        @now = now
      end

      def call
        validation = validation_failure
        return validation if validation
        unless CustomerPolicy.order_owned_by?(order: @order, actor: @actor)
          return failure("customer_dispute_order_unavailable")
        end

        existing = existing_event
        return idempotency_result(existing) if existing

        payment = @order.primary_succeeded_payment_record
        return failure("customer_dispute_payment_unavailable") unless payment

        result = nil
        Commerce::Dispute.transaction do
          order, payment, refunds, disputes = Commerce::FinancialLocking
            .lock_order_payment_refunds_disputes!(
              order_id: @order.id,
              payment_record_id: payment.id
            )

          unless CustomerPolicy.order_owned_by?(order:, actor: @actor)
            result = failure("customer_dispute_order_unavailable")
            next
          end

          existing = existing_event
          if existing
            result = idempotency_result(existing)
            next
          end

          unless CustomerPolicy.create_allowed?(
            order:,
            payment:,
            refunds:,
            disputes:
          )
            result = create_state_failure(refunds:, disputes:)
            next
          end

          available_cents = CustomerPolicy.available_cents(
            payment:,
            refunds:,
            disputes:
          )
          amount_cents = requested_amount_cents(available_cents)
          unless amount_cents.positive? && amount_cents <= available_cents
            result = failure("customer_dispute_amount_invalid")
            next
          end

          dispute = Commerce::Dispute.create!(
            order:,
            payment_record: payment,
            customer_opened_by: @actor,
            customer_opened_at: @now,
            provider: payment.provider,
            provider_dispute_id: customer_provider_dispute_id,
            kind: "dispute",
            status: "open",
            provider_status: "customer_opened",
            risk_level: "medium",
            reason_code: "customer_reported",
            amount_cents:,
            liability_cents: amount_cents,
            offset_cents: 0,
            currency: payment.currency.to_s.upcase,
            metadata: {
              "customer_origin" => true,
              "payment_amount_cents" => payment.amount_cents,
              "reserved_refund_cents" => reserved_refund_cents(refunds)
            }
          )

          rights = Commerce::Disputes::RightsPolicy.call(
            dispute:,
            action: "freeze",
            idempotency_prefix: event_idempotency_key,
            actor: @actor,
            reason: "customer_payment_dispute_opened"
          )
          ensure_success!(dispute, rights, "customer_dispute_rights_failed")

          event = Commerce::DisputeEvent.create!(
            dispute:,
            actor: @actor,
            idempotency_key: event_idempotency_key,
            request_id: @request_id,
            source: "manual",
            event_type: "customer_opened",
            from_status: nil,
            to_status: dispute.status,
            note: @description,
            payload_digest: request_fingerprint,
            metadata: {
              "request_fingerprint" => request_fingerprint,
              "customer_reason_kind" => @reason_kind,
              "amount_cents" => dispute.amount_cents
            }
          )
          Administration::AuditLogger.call(
            actor: @actor,
            action: "commerce.customer_dispute_opened",
            resource: dispute,
            request_id: @request_id,
            reason: @description,
            before_state: {},
            after_state: audit_state(dispute),
            metadata: {
              dispute_event_id: event.id,
              order_public_id: order.public_id,
              customer_reason_kind: @reason_kind
            },
            ip_address: @ip_address,
            user_agent: @user_agent
          )
          notification = Commerce::Disputes::CustomerNotifier.call(event:)
          ensure_success!(dispute, notification, "customer_dispute_notification_failed")

          result = ServiceResult.success(
            dispute:,
            event:,
            idempotent: false
          )
        end

        result
      rescue Commerce::FinancialLocking::BindingMismatch
        failure("customer_dispute_payment_binding_mismatch")
      rescue ActiveRecord::RecordNotUnique
        idempotency_result(existing_event) || failure("customer_dispute_already_exists")
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def validation_failure
        return failure("customer_dispute_request_id_invalid") unless @request_id
        return failure("customer_dispute_reason_invalid") unless REASON_KINDS.include?(@reason_kind)
        if @description.length < MIN_DESCRIPTION_LENGTH
          return failure("customer_dispute_description_too_short")
        end
        if @description.length > MAX_DESCRIPTION_LENGTH
          return failure("customer_dispute_description_too_long")
        end
        if @amount_cents.present? && !integer_string?(@amount_cents)
          return failure("customer_dispute_amount_invalid")
        end

        nil
      end

      def create_state_failure(refunds:, disputes:)
        if refunds.any? { |refund| Commerce::Refund::IN_FLIGHT_STATUSES.include?(refund.status) }
          return failure("customer_dispute_refund_in_flight")
        end
        return failure("customer_dispute_already_exists") if disputes.any?(&:customer_origin?)
        if disputes.any? { |dispute| dispute.liability_cents.positive? && CustomerPolicy.active_exposure?(dispute) }
          return failure("customer_dispute_payment_already_disputed")
        end

        failure("customer_dispute_unavailable")
      end

      def requested_amount_cents(available_cents)
        @amount_cents.present? ? @amount_cents.to_i : available_cents
      end

      def reserved_refund_cents(refunds)
        refunds.sum do |refund|
          Commerce::Refund::RESERVED_STATUSES.include?(refund.status) ? refund.amount_cents : 0
        end
      end

      def existing_event
        Commerce::DisputeEvent.find_by(idempotency_key: event_idempotency_key)
      end

      def idempotency_result(event)
        return unless event
        unless secure_match?(event.metadata["request_fingerprint"], request_fingerprint)
          return failure("customer_dispute_idempotency_conflict")
        end
        unless event.event_type == "customer_opened" && event.actor_id == @actor.id
          return failure("customer_dispute_idempotency_conflict")
        end

        ServiceResult.success(dispute: event.dispute, event:, idempotent: true)
      end

      def request_fingerprint
        @request_fingerprint ||= Digest::SHA256.hexdigest(
          JSON.generate(
            actor_id: @actor&.id,
            order_id: @order&.id,
            action: "customer_dispute_open",
            request_id: @request_id,
            reason_kind: @reason_kind,
            description: @description,
            amount_cents: @amount_cents.present? ? @amount_cents.to_i : "maximum"
          )
        )
      end

      def event_idempotency_key
        "dispute-customer-open:#{@actor&.id}:#{@request_id}"
      end

      def customer_provider_dispute_id
        digest = Digest::SHA256.hexdigest("#{@actor.id}:#{@request_id}")
        "#{Commerce::Dispute::CUSTOMER_PROVIDER_ID_PREFIX}#{digest.first(40)}"
      end

      def audit_state(dispute)
        {
          status: dispute.status,
          amount_cents: dispute.amount_cents,
          liability_cents: dispute.liability_cents,
          offset_cents: dispute.offset_cents,
          rights_status: dispute.rights_status,
          customer_opened_by_id: dispute.customer_opened_by_id
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

      def integer_string?(value)
        value.to_s.match?(/\A\d+\z/)
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
