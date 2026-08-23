# frozen_string_literal: true

module Commerce
  module Disputes
    module CustomerPolicy
      CREATE_ORDER_STATUSES = %w[
        paid processing fulfilling fulfilled completed
      ].freeze

      module_function

      def order_owned_by?(order:, actor:)
        actor&.persisted? == true &&
          actor.session_eligible? &&
          order&.persisted? &&
          order.user_id == actor.id
      end

      def create_allowed?(order:, payment:, refunds: nil, disputes: nil)
        return false unless order && payment&.succeeded?
        return false unless CREATE_ORDER_STATUSES.include?(order.status)
        return false unless payment.store_order_id == order.id

        refunds ||= payment.refunds.to_a
        disputes ||= payment.disputes.to_a
        return false if refunds.any? { |refund| Commerce::Refund::IN_FLIGHT_STATUSES.include?(refund.status) }
        return false if disputes.any?(&:customer_origin?)
        return false if disputes.any? { |dispute| active_exposure?(dispute) }

        available_cents(payment:, refunds:, disputes:).positive?
      end

      def available_cents(payment:, refunds: nil, disputes: nil)
        refunds ||= payment.refunds.to_a
        disputes ||= payment.disputes.to_a
        reserved_refunds = refunds.sum do |refund|
          Commerce::Refund::RESERVED_STATUSES.include?(refund.status) ? refund.amount_cents : 0
        end
        dispute_liability = disputes.sum do |dispute|
          active_exposure?(dispute) ? dispute.liability_cents : 0
        end

        [ payment.amount_cents - reserved_refunds - dispute_liability, 0 ].max
      end

      def active_financial_dispute?(payment)
        payment.disputes.active_exposure.where("liability_cents > 0").exists?
      end

      def evidence_allowed?(dispute:, actor:)
        order_owned_by?(order: dispute&.order, actor:) && dispute.customer_evidence_allowed?
      end

      def active_exposure?(dispute)
        Commerce::Dispute::ACTIVE_EXPOSURE_STATUSES.include?(dispute.status) ||
          (dispute.closed? && %w[lost accepted_loss].include?(dispute.resolution))
      end
    end
  end
end
