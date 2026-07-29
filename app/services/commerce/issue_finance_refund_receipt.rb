# frozen_string_literal: true

require "digest"

module Commerce
  class IssueFinanceRefundReceipt < ApplicationService
    def initialize(refund:, actor: nil, issued_at: Time.current)
      @refund = refund
      @actor = actor
      @issued_at = issued_at
    end

    def call
      document = nil
      idempotent = false

      FinanceDocument.transaction do
        order = Commerce::Order.lock.find(@refund.store_order_id)
        refund = Commerce::Refund.lock.find(@refund.id)
        return failure("finance_refund_not_completed") unless refund.completed?

        existing = FinanceDocument.refund_receipt
          .where(store_refund_id: refund.id)
          .order(version: :desc)
          .first
        if existing
          return failure("finance_refund_receipt_conflict") unless receipt_matches_refund?(existing, refund)

          document = existing
          idempotent = true
          next
        end

        invoice_result = IssueFinanceInvoice.call(
          order:,
          payment_record: refund.payment_record,
          actor: @actor,
          issued_at: @issued_at
        )
        return invoice_result if invoice_result.failure?

        invoice = invoice_result.value.fetch(:document)
        allocation = allocate_tax(invoice, refund)
        document = FinanceDocument.create!(
          order:,
          refund:,
          tax_snapshot: invoice.tax_snapshot,
          document_kind: "refund_receipt",
          document_number: "CRN-#{order.order_number}-#{refund.id}",
          version: 1,
          status: "issued",
          channel: refund.payment_record.provider,
          currency: refund.payment_record.currency,
          net_amount_cents: refund.amount_cents - allocation.fetch(:tax_cents),
          tax_amount_cents: allocation.fetch(:tax_cents),
          gross_amount_cents: refund.amount_cents,
          source_digest: receipt_digest(refund, allocation),
          content_snapshot: receipt_content(order, refund, invoice, allocation),
          issued_at: @issued_at,
          retention_until: FinanceRetentionPolicy.document_retention_until(from: @issued_at)
        )
        record_issued!(document, invoice, allocation)
      end

      ServiceResult.success(document:, idempotent:)
    rescue ActiveRecord::RecordNotUnique
      document = FinanceDocument.refund_receipt
        .where(store_refund_id: @refund.id)
        .order(version: :desc)
        .first!
      return failure("finance_refund_receipt_conflict") unless receipt_matches_refund?(document, @refund.reload)

      ServiceResult.success(document:, idempotent: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash, code: "finance_refund_receipt_invalid")
    end

    private

    def allocate_tax(invoice, refund)
      prior = FinanceDocument.refund_receipt
        .where(store_order_id: refund.store_order_id, version: 1)
        .lock
        .to_a
      prior_gross_cents = prior.sum(&:gross_amount_cents)
      prior_tax_cents = prior.sum(&:tax_amount_cents)
      allocation_sequence = prior.length + 1

      cumulative_gross_cents = [
        prior_gross_cents + refund.amount_cents,
        invoice.gross_amount_cents
      ].min
      cumulative_tax_cents =
        if invoice.gross_amount_cents.zero?
          0
        else
          divide_half_up(
            invoice.tax_amount_cents * cumulative_gross_cents,
            invoice.gross_amount_cents
          )
        end
      tax_cents = (cumulative_tax_cents - prior_tax_cents).clamp(0, refund.amount_cents)

      {
        allocation_sequence:,
        prior_gross_cents:,
        prior_tax_cents:,
        cumulative_gross_cents:,
        cumulative_tax_cents:,
        tax_cents:
      }
    end

    def divide_half_up(numerator, denominator)
      ((2 * numerator) + denominator) / (2 * denominator)
    end

    def receipt_digest(refund, allocation)
      Digest::SHA256.hexdigest(
        JSON.generate(
          canonicalize(
            {
            refund_id: refund.id,
            order_id: refund.store_order_id,
            payment_record_id: refund.payment_record_id,
            amount_cents: refund.amount_cents,
            currency: refund.payment_record.currency,
            provider: refund.payment_record.provider,
            provider_refund_id: refund.provider_refund_id,
            allocation:
            }
          )
        )
      )
    end

    def receipt_matches_refund?(document, refund)
      allocation = document.content_snapshot["allocation"]
      return false unless allocation.is_a?(Hash)

      document.store_order_id == refund.store_order_id &&
        document.gross_amount_cents == refund.amount_cents &&
        document.currency == refund.payment_record.currency &&
        document.channel == refund.payment_record.provider &&
        ActiveSupport::SecurityUtils.secure_compare(
          document.source_digest,
          receipt_digest(refund, allocation)
        )
    end

    def receipt_content(order, refund, invoice, allocation)
      {
        schema_version: 1,
        order_public_id: order.public_id,
        order_number: order.order_number,
        refund_id: refund.id,
        payment_record_id: refund.payment_record_id,
        provider_refund_id: refund.provider_refund_id,
        invoice_public_id: invoice.public_id,
        invoice_number: invoice.document_number,
        reason: refund.reason,
        provider_status: refund.provider_status,
        allocation:,
        tax: {
          rate_bps: invoice.tax_snapshot.tax_rate_bps,
          jurisdiction_country: invoice.tax_snapshot.jurisdiction_country,
          jurisdiction_region: invoice.tax_snapshot.jurisdiction_region,
          tax_code: invoice.tax_snapshot.tax_code,
          rounding_mode: invoice.tax_snapshot.rounding_mode
        }
      }.compact
    end

    def canonicalize(value)
      case value
      when Hash
        value.to_h.stringify_keys.sort.to_h.transform_values { |nested| canonicalize(nested) }
      when Array
        value.map { |nested| canonicalize(nested) }
      else
        value
      end
    end

    def record_issued!(document, invoice, allocation)
      state = document_state(document)
      document.events.create!(
        event_type: "issued",
        actor: @actor,
        after_state: state,
        metadata: {
          invoice_public_id: invoice.public_id,
          allocation_sequence: allocation.fetch(:allocation_sequence)
        },
        created_at: @issued_at
      )
      Administration::AuditLogger.call(
        actor: @actor,
        action: "commerce.finance_refund_receipt_issued",
        resource: document,
        after_state: state,
        metadata: {
          order_public_id: document.order.public_id,
          refund_id: document.store_refund_id,
          document_number: document.document_number,
          version: document.version,
          allocation_sequence: allocation.fetch(:allocation_sequence)
        }
      )
    end

    def document_state(document)
      {
        status: document.status,
        document_number: document.document_number,
        version: document.version,
        currency: document.currency,
        net_amount_cents: document.net_amount_cents,
        tax_amount_cents: document.tax_amount_cents,
        gross_amount_cents: document.gross_amount_cents
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
