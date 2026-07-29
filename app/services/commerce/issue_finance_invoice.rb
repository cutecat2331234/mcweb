# frozen_string_literal: true

require "digest"

module Commerce
  class IssueFinanceInvoice < ApplicationService
    ELIGIBLE_ORDER_STATUSES = %w[paid processing fulfilling fulfilled completed refunded].freeze

    def initialize(order:, payment_record: nil, actor: nil, issued_at: Time.current)
      @order = order
      @payment_record = payment_record
      @actor = actor
      @issued_at = issued_at
    end

    def call
      document = nil
      idempotent = false

      FinanceDocument.transaction do
        order = Commerce::Order.lock.find(@order.id)
        return failure("finance_invoice_order_not_paid") unless order.status.in?(ELIGIBLE_ORDER_STATUSES)

        existing = FinanceDocument.invoice
          .where(store_order_id: order.id)
          .order(version: :desc)
          .first
        if existing
          document = existing
          idempotent = true
          next
        end

        snapshot_result = CaptureFinanceTaxSnapshot.call(order:, actor: @actor, captured_at: @issued_at)
        return snapshot_result if snapshot_result.failure?

        tax_snapshot = snapshot_result.value.fetch(:snapshot)
        payment = eligible_payment(order)
        channel = payment&.provider.to_s.presence || (order.total_cents.zero? ? "internal" : "unknown")
        source_digest = invoice_digest(order:, tax_snapshot:, channel:)
        document = FinanceDocument.create!(
          order:,
          tax_snapshot:,
          document_kind: "invoice",
          document_number: "INV-#{order.order_number}",
          version: 1,
          status: "issued",
          channel:,
          currency: tax_snapshot.currency,
          net_amount_cents: tax_snapshot.taxable_base_cents,
          tax_amount_cents: tax_snapshot.tax_cents,
          gross_amount_cents: tax_snapshot.gross_cents,
          source_digest:,
          content_snapshot: invoice_content(order, tax_snapshot, payment),
          issued_at: @issued_at,
          retention_until: FinanceRetentionPolicy.document_retention_until(from: @issued_at)
        )
        record_issued!(document, payment)
      end

      ServiceResult.success(document:, idempotent:)
    rescue ActiveRecord::RecordNotUnique
      document = FinanceDocument.invoice
        .where(store_order_id: @order.id)
        .order(version: :desc)
        .first!
      ServiceResult.success(document:, idempotent: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash, code: "finance_invoice_invalid")
    end

    private

    def eligible_payment(order)
      return @payment_record if @payment_record&.store_order_id == order.id && @payment_record.succeeded?

      order.primary_succeeded_payment_record
    end

    def invoice_digest(order:, tax_snapshot:, channel:)
      Digest::SHA256.hexdigest(
        JSON.generate(
          {
            order_id: order.id,
            tax_snapshot_id: tax_snapshot.id,
            tax_source_digest: tax_snapshot.source_digest,
            channel:,
            currency: tax_snapshot.currency,
            gross_cents: tax_snapshot.gross_cents
          }
        )
      )
    end

    def invoice_content(order, tax_snapshot, payment)
      {
        schema_version: 1,
        order_public_id: order.public_id,
        order_number: order.order_number,
        customer_public_id: order.user.public_id,
        payment_record_id: payment&.id,
        tender: {
          provider_cents: order.total_cents.to_i,
          gift_card_cents: order.gift_card_amount_cents.to_i,
          store_credit_cents: order.store_credit_amount_cents.to_i
        },
        tax: {
          rate_bps: tax_snapshot.tax_rate_bps,
          jurisdiction_country: tax_snapshot.jurisdiction_country,
          jurisdiction_region: tax_snapshot.jurisdiction_region,
          tax_code: tax_snapshot.tax_code,
          pricing_mode: tax_snapshot.pricing_mode,
          rounding_mode: tax_snapshot.rounding_mode
        },
        lines: tax_snapshot.line_snapshot
      }.compact
    end

    def record_issued!(document, payment)
      document.events.create!(
        event_type: "issued",
        actor: @actor,
        after_state: document_state(document),
        metadata: { payment_record_id: payment&.id }.compact,
        created_at: @issued_at
      )
      Administration::AuditLogger.call(
        actor: @actor,
        action: "commerce.finance_invoice_issued",
        resource: document,
        after_state: document_state(document),
        metadata: {
          order_public_id: document.order.public_id,
          document_number: document.document_number,
          version: document.version,
          payment_record_id: payment&.id
        }.compact
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
