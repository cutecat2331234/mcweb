# frozen_string_literal: true

module Commerce
  module Disputes
    class RebalanceExposure < ApplicationService
      def initialize(payment_record:, trigger_idempotency:)
        @payment_record = payment_record
        @trigger_idempotency = trigger_idempotency.to_s
      end

      def call
        return ServiceResult.failure(error: "dispute_idempotency_invalid") if @trigger_idempotency.blank?

        changed = 0
        restored = 0
        result = nil

        Commerce::Dispute.transaction do
          _order, payment, disputes = Commerce::FinancialLocking.lock_order_payment_disputes!(
            order_id: @payment_record.store_order_id,
            payment_record_id: @payment_record.id
          )
          refunded_cents = payment.refunds.completed.sum(:amount_cents)
          available_cents = [ payment.amount_cents - refunded_cents, 0 ].max

          disputes.each do |dispute|
            target_liability =
              if released_exposure?(dispute)
                0
              else
                [ dispute.amount_cents, available_cents ].min
              end
            available_cents -= target_liability
            next if dispute.liability_cents == target_liability

            before = exposure_state(dispute)
            dispute.update!(
              liability_cents: target_liability,
              offset_cents: dispute.amount_cents - target_liability,
              metadata: dispute.metadata.merge(
                "payment_amount_cents" => payment.amount_cents,
                "completed_refund_cents" => refunded_cents,
                "unallocated_payment_cents" => available_cents
              )
            )

            if target_liability.zero? &&
                (dispute.rights_frozen? || dispute.rights_revoked?)
              rights = Commerce::Disputes::RightsPolicy.call(
                dispute: dispute,
                action: "restore",
                idempotency_prefix: "#{event_key(dispute)}:rights",
                reason: "financial_exposure_offset"
              )
              unless rights.success?
                dispute.errors.add(:base, rights.error.presence || "rights restoration failed")
                raise ActiveRecord::RecordInvalid.new(dispute)
              end
              restored += rights.value.fetch(:changed)
            end

            event = Commerce::DisputeEvent.create!(
              dispute: dispute,
              idempotency_key: event_key(dispute),
              source: "system",
              event_type: "exposure_rebalanced",
              from_status: dispute.status,
              to_status: dispute.status,
              metadata: {
                "before" => before,
                "after" => exposure_state(dispute),
                "trigger" => @trigger_idempotency
              }
            )
            Administration::AuditLogger.call(
              action: "commerce.dispute_exposure_rebalanced",
              resource: dispute,
              before_state: before,
              after_state: exposure_state(dispute),
              metadata: {
                dispute_event_id: event.id,
                trigger: @trigger_idempotency
              }
            )
            changed += 1
          end

          allocated = disputes.sum(&:liability_cents)
          result = ServiceResult.success(
            changed: changed,
            rights_restored: restored,
            payment_amount_cents: payment.amount_cents,
            refunded_cents: refunded_cents,
            liability_cents: allocated,
            available_cents: [ payment.amount_cents - refunded_cents - allocated, 0 ].max
          )
        end

        result
      rescue ActiveRecord::RecordNotUnique
        ServiceResult.success(changed: 0, idempotent: true)
      rescue Commerce::FinancialLocking::BindingMismatch
        ServiceResult.failure(error: "dispute_payment_binding_mismatch")
      rescue ActiveRecord::RecordInvalid => error
        ServiceResult.failure(errors: error.record.errors.to_hash)
      end

      private

      def released_exposure?(dispute)
        dispute.won? ||
          dispute.withdrawn? ||
          (dispute.closed? && %w[won withdrawn].include?(dispute.resolution))
      end

      def exposure_state(dispute)
        {
          "amount_cents" => dispute.amount_cents,
          "liability_cents" => dispute.liability_cents,
          "offset_cents" => dispute.offset_cents,
          "rights_status" => dispute.rights_status
        }
      end

      def event_key(dispute)
        "dispute-rebalance:#{Digest::SHA256.hexdigest(@trigger_idempotency).first(24)}:#{dispute.id}"
      end
    end
  end
end
