# frozen_string_literal: true

module Commerce
  module Disputes
    class ApplyChannelEvent < ApplicationService
      PROVIDER_STATUS_MAP = {
        "open" => "open",
        "warning_needs_response" => "evidence_required",
        "needs_response" => "evidence_required",
        "evidence_required" => "evidence_required",
        "evidence_submitted" => "evidence_submitted",
        "warning_under_review" => "under_review",
        "under_review" => "under_review",
        "won" => "won",
        "lost" => "lost",
        "charge_refunded" => "withdrawn",
        "withdrawn" => "withdrawn",
        "warning_closed" => "withdrawn"
      }.freeze
      STATUS_RANK = {
        "open" => 0,
        "evidence_required" => 1,
        "evidence_submitted" => 2,
        "under_review" => 3,
        "won" => 4,
        "lost" => 4,
        "withdrawn" => 4,
        "closed" => 5
      }.freeze

      def initialize(
        provider:,
        provider_event_id:,
        provider_dispute_id:,
        payment_record:,
        event_type:,
        provider_status:,
        amount_cents:,
        currency:,
        occurred_at:,
        sequence: nil,
        evidence_due_at: nil,
        risk_level: "high",
        reason_code: nil,
        kind: "chargeback",
        payload_digest: nil,
        webhook_event: nil
      )
        @provider = provider.to_s
        @provider_event_id = provider_event_id.to_s
        @provider_dispute_id = provider_dispute_id.to_s
        @payment_record = payment_record
        @event_type = event_type.to_s
        @provider_status = provider_status.to_s
        @amount_cents = amount_cents.to_i
        @currency = currency.to_s.upcase
        @occurred_at = coerce_time(occurred_at)
        @sequence = integer_or_nil(sequence)
        @evidence_due_at = coerce_time(evidence_due_at)
        @risk_level = normalized_risk(risk_level)
        @reason_code = safe_identifier(reason_code)
        @kind = %w[dispute chargeback].include?(kind.to_s) ? kind.to_s : "chargeback"
        @payload_digest = payload_digest.to_s.presence || calculated_payload_digest
        @webhook_event = webhook_event
      end

      def call
        validation = validation_failure
        return validation if validation

        result = nil
        Commerce::Dispute.transaction do
          order, @payment_record = Commerce::FinancialLocking.lock_order_payment!(
            order_id: @payment_record.store_order_id,
            payment_record_id: @payment_record.id
          )
          result = existing_event_result
          next if result

          dispute = find_or_create_dispute!(order)
          dispute.lock!
          dispute.reload

          from_status = dispute.status
          target_status = mapped_status(dispute)
          stale = stale_event?(dispute, target_status)

          unless stale
            assign_channel_state!(dispute, target_status)
            rebalance_dispute!(dispute)
            apply_rights_policy!(dispute)
          end

          event = Commerce::DisputeEvent.create!(
            dispute: dispute,
            payment_webhook_event: @webhook_event,
            idempotency_key: event_idempotency_key,
            source: "channel",
            event_type: @event_type,
            provider_event_id: @provider_event_id,
            provider_status: @provider_status,
            from_status: from_status,
            to_status: dispute.status,
            provider_occurred_at: @occurred_at,
            provider_sequence: @sequence,
            payload_digest: @payload_digest,
            metadata: event_metadata(dispute, stale:)
          )

          Administration::AuditLogger.call(
            action: stale ?
              "commerce.dispute_channel_event_ignored" :
              "commerce.dispute_channel_event_applied",
            resource: dispute,
            before_state: { status: from_status },
            after_state: {
              status: dispute.status,
              amount_cents: dispute.amount_cents,
              liability_cents: dispute.liability_cents,
              offset_cents: dispute.offset_cents,
              rights_status: dispute.rights_status
            },
            metadata: {
              dispute_event_id: event.id,
              provider: @provider,
              provider_event_id: @provider_event_id,
              provider_status: @provider_status,
              stale: stale
            }
          )

          result = ServiceResult.success(
            dispute: dispute,
            event: event,
            idempotent: false,
            stale: stale
          )
        end

        result
      rescue Commerce::FinancialLocking::BindingMismatch
        ServiceResult.failure(error: "dispute_payment_binding_mismatch")
      rescue ActiveRecord::RecordNotUnique
        existing_event_result ||
          ServiceResult.failure(error: "dispute_channel_event_conflict")
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def validation_failure
        return ServiceResult.failure(error: "dispute_payment_invalid") unless @payment_record&.persisted?
        return ServiceResult.failure(error: "dispute_payment_invalid") unless @payment_record.succeeded?
        return ServiceResult.failure(error: "dispute_provider_mismatch") unless @payment_record.provider == @provider
        return ServiceResult.failure(error: "dispute_event_identity_invalid") if @provider_event_id.blank? || @provider_dispute_id.blank?
        return ServiceResult.failure(error: "dispute_event_type_invalid") if @event_type.blank?
        return ServiceResult.failure(error: "dispute_amount_invalid") unless @amount_cents.positive?
        return ServiceResult.failure(error: "dispute_amount_exceeds_payment") if @amount_cents > @payment_record.amount_cents
        return ServiceResult.failure(error: "dispute_currency_mismatch") unless @currency.casecmp?(@payment_record.currency.to_s)
        return ServiceResult.failure(error: "dispute_event_time_invalid") unless @occurred_at

        nil
      end

      def existing_event_result
        existing = Commerce::DisputeEvent.find_by(idempotency_key: event_idempotency_key)
        return unless existing
        return ServiceResult.failure(error: "dispute_channel_event_conflict") unless secure_match?(
          existing.payload_digest,
          @payload_digest
        )

        ServiceResult.success(
          dispute: existing.dispute,
          event: existing,
          idempotent: true,
          stale: existing.metadata["stale"] == true
        )
      end

      def find_or_create_dispute!(order)
        Commerce::Dispute.find_or_initialize_by(
          provider: @provider,
          provider_dispute_id: @provider_dispute_id
        ).tap do |dispute|
          if dispute.new_record?
            dispute.assign_attributes(
              order: order,
              payment_record: @payment_record,
              kind: @kind,
              status: "open",
              provider_status: @provider_status,
              risk_level: @risk_level,
              reason_code: @reason_code,
              amount_cents: @amount_cents,
              liability_cents: @amount_cents,
              offset_cents: 0,
              currency: @currency,
              evidence_due_at: @evidence_due_at,
              metadata: {}
            )
            dispute.save!
          elsif dispute.payment_record_id != @payment_record.id ||
              dispute.store_order_id != order.id
            raise ActiveRecord::RecordInvalid.new(dispute)
          end
          dispute
        end
      end

      def assign_channel_state!(dispute, target_status)
        resolution =
          case target_status
          when "won", "lost", "withdrawn" then target_status
          else dispute.resolution
          end

        dispute.assign_attributes(
          status: target_status,
          provider_status: @provider_status,
          risk_level: @risk_level,
          reason_code: @reason_code.presence || dispute.reason_code,
          amount_cents: @amount_cents,
          currency: @currency,
          evidence_due_at: @evidence_due_at || dispute.evidence_due_at,
          latest_provider_event_at: @occurred_at,
          latest_provider_sequence: @sequence || dispute.latest_provider_sequence,
          latest_provider_event_id: @provider_event_id,
          resolution: resolution,
          metadata: dispute.metadata.merge(
            "last_channel_event_type" => @event_type
          )
        )
      end

      def rebalance_dispute!(dispute)
        refunded_cents = @payment_record.refunds.completed.sum(:amount_cents)
        other_liability = @payment_record.disputes
          .active_exposure
          .where.not(id: dispute.id)
          .sum(:liability_cents)
        available_cents = [
          @payment_record.amount_cents - refunded_cents - other_liability,
          0
        ].max
        liability_cents =
          if %w[won withdrawn].include?(dispute.status)
            0
          else
            [ dispute.amount_cents, available_cents ].min
          end

        dispute.assign_attributes(
          liability_cents: liability_cents,
          offset_cents: dispute.amount_cents - liability_cents,
          metadata: dispute.metadata.merge(
            "payment_amount_cents" => @payment_record.amount_cents,
            "completed_refund_cents" => refunded_cents,
            "other_dispute_liability_cents" => other_liability,
            "unallocated_payment_cents" => [
              available_cents - liability_cents,
              0
            ].max
          )
        )
        dispute.save!
      end

      def apply_rights_policy!(dispute)
        action =
          if %w[won withdrawn].include?(dispute.status) || dispute.liability_cents.zero?
            "restore" unless dispute.rights_unchanged? || dispute.rights_restored?
          elsif dispute.lost? || dispute.risk_critical?
            "revoke"
          elsif %w[medium high].include?(dispute.risk_level)
            "freeze" if dispute.rights_unchanged? || dispute.rights_restored?
          end
        return unless action

        result = Commerce::Disputes::RightsPolicy.call(
          dispute: dispute,
          action: action,
          idempotency_prefix: event_idempotency_key,
          reason: "channel_policy_#{dispute.status}"
        )
        return if result.success?

        dispute.errors.add(:base, result.error.presence || "rights policy failed")
        raise ActiveRecord::RecordInvalid.new(dispute)
      end

      def mapped_status(dispute)
        PROVIDER_STATUS_MAP.fetch(@provider_status) do
          @event_type.end_with?(".created") ? "evidence_required" : dispute.status
        end
      end

      def stale_event?(dispute, target_status)
        if @sequence && dispute.latest_provider_sequence
          return true if @sequence < dispute.latest_provider_sequence
          if @sequence == dispute.latest_provider_sequence
            return true if STATUS_RANK.fetch(target_status) < STATUS_RANK.fetch(dispute.status)
          end
        elsif dispute.latest_provider_event_at && @occurred_at < dispute.latest_provider_event_at
          return true
        end

        false
      end

      def event_metadata(dispute, stale:)
        {
          "stale" => stale,
          "amount_cents" => dispute.amount_cents,
          "liability_cents" => dispute.liability_cents,
          "offset_cents" => dispute.offset_cents,
          "currency" => dispute.currency,
          "risk_level" => dispute.risk_level,
          "rights_status" => dispute.rights_status
        }
      end

      def event_idempotency_key
        "dispute-channel:#{@provider}:#{@provider_event_id}"
      end

      def calculated_payload_digest
        Digest::SHA256.hexdigest(
          JSON.generate(
            {
              provider: @provider,
              event_id: @provider_event_id,
              dispute_id: @provider_dispute_id,
              event_type: @event_type,
              provider_status: @provider_status,
              amount_cents: @amount_cents,
              currency: @currency,
              occurred_at: @occurred_at&.iso8601(6),
              sequence: @sequence,
              evidence_due_at: @evidence_due_at&.iso8601(6),
              risk_level: @risk_level,
              reason_code: @reason_code
            }
          )
        )
      end

      def coerce_time(value)
        case value
        when Time, ActiveSupport::TimeWithZone then value
        when Integer then Time.zone.at(value)
        else Time.zone.parse(value.to_s) if value.present?
        end
      rescue ArgumentError
        nil
      end

      def integer_or_nil(value)
        Integer(value) if value.present?
      rescue ArgumentError, TypeError
        nil
      end

      def normalized_risk(value)
        normalized = value.to_s
        Commerce::Dispute::RISK_LEVELS.include?(normalized) ? normalized : "high"
      end

      def safe_identifier(value)
        value.to_s.downcase.gsub(/[^a-z0-9_.-]+/, "_").first(100).presence
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
