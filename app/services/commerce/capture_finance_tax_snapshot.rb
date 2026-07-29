# frozen_string_literal: true

require "digest"

module Commerce
  class CaptureFinanceTaxSnapshot < ApplicationService
    CALCULATION_VERSION = 1
    MAX_TAX_RATE_BPS = 100_000

    def initialize(order:, actor: nil, captured_at: Time.current)
      @order = order
      @actor = actor
      @captured_at = captured_at
    end

    def call
      snapshot = nil
      idempotent = false

      FinanceTaxSnapshot.transaction do
        order = Commerce::Order.lock.find(@order.id)
        existing = FinanceTaxSnapshot.find_by(store_order_id: order.id)

        if existing
          return failure("finance_tax_snapshot_conflict") unless snapshot_matches_order?(existing, order)

          snapshot = existing
          idempotent = true
          next
        end

        attributes = snapshot_attributes(order)
        snapshot = FinanceTaxSnapshot.create!(attributes.merge(order:))
        Administration::AuditLogger.call(
          actor: @actor,
          action: "commerce.finance_tax_snapshot_captured",
          resource: snapshot,
          after_state: audit_state(snapshot),
          metadata: {
            order_public_id: order.public_id,
            calculation_version: CALCULATION_VERSION
          }
        )
      end

      ServiceResult.success(snapshot:, idempotent:)
    rescue ActiveRecord::RecordNotUnique
      existing = FinanceTaxSnapshot.find_by!(store_order_id: @order.id)
      return failure("finance_tax_snapshot_conflict") unless snapshot_matches_order?(existing, @order.reload)

      ServiceResult.success(snapshot: existing, idempotent: true)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash, code: "finance_tax_snapshot_invalid")
    end

    private

    def snapshot_attributes(order)
      rule = current_rule(order)
      gross_cents = captured_gross_cents(order)
      taxable_base_cents = inclusive_taxable_base(gross_cents, rule.fetch(:tax_rate_bps))
      tax_cents = gross_cents - taxable_base_cents
      line_snapshot = line_snapshot(order)
      source_digest = digest_for(
        order:,
        rule:,
        gross_cents:,
        line_snapshot:
      )

      {
        tax_rate_bps: rule.fetch(:tax_rate_bps),
        taxable_base_cents:,
        tax_cents:,
        gross_cents:,
        currency: order.currency,
        pricing_mode: "inclusive",
        rounding_mode: "half_up",
        jurisdiction_country: rule.fetch(:jurisdiction_country),
        jurisdiction_region: rule[:jurisdiction_region],
        tax_code: rule.fetch(:tax_code),
        calculation_version: CALCULATION_VERSION,
        source_digest:,
        line_snapshot:,
        captured_at: @captured_at,
        retention_until: FinanceRetentionPolicy.source_retention_until(from: @captured_at)
      }
    end

    def current_rule(order)
      shipping = order.shipping_address.to_h.stringify_keys
      rate = integer_setting("store.tax_rate_bps", 0).clamp(0, MAX_TAX_RATE_BPS)
      {
        tax_rate_bps: rate,
        jurisdiction_country:
          shipping["country_code"].presence ||
            shipping["country"].presence ||
            SiteSetting.get("store.tax_country", "CN").to_s.upcase.first(2),
        jurisdiction_region:
          shipping["province"].presence ||
            SiteSetting.get("store.tax_region", "").to_s.strip.presence,
        tax_code: SiteSetting.get("store.tax_code", "standard").to_s.strip.presence || "standard"
      }
    end

    def snapshot_matches_order?(snapshot, order)
      rule = {
        tax_rate_bps: snapshot.tax_rate_bps,
        jurisdiction_country: snapshot.jurisdiction_country,
        jurisdiction_region: snapshot.jurisdiction_region,
        tax_code: snapshot.tax_code
      }
      gross_cents = captured_gross_cents(order)
      lines = line_snapshot(order)
      expected = digest_for(order:, rule:, gross_cents:, line_snapshot: lines)

      ActiveSupport::SecurityUtils.secure_compare(snapshot.source_digest, expected)
    end

    def captured_gross_cents(order)
      [
        order.subtotal_cents.to_i -
          order.discount_cents.to_i +
          order.shipping_cents.to_i +
          order.gift_wrap_cents.to_i,
        0
      ].max
    end

    def line_snapshot(order)
      {
        items: order.items.order(:id).map do |item|
          {
            order_item_id: item.id,
            product_name: item.product_name,
            variant_name: item.variant_name,
            quantity: item.quantity,
            unit_price_cents: item.unit_price_cents,
            gross_cents: item.total_cents
          }.compact
        end,
        discount_cents: order.discount_cents.to_i,
        shipping_cents: order.shipping_cents.to_i,
        gift_wrap_cents: order.gift_wrap_cents.to_i,
        gift_card_tender_cents: order.gift_card_amount_cents.to_i,
        store_credit_tender_cents: order.store_credit_amount_cents.to_i,
        payable_cents: order.total_cents.to_i
      }
    end

    def digest_for(order:, rule:, gross_cents:, line_snapshot:)
      Digest::SHA256.hexdigest(
        JSON.generate(
          {
            order_id: order.id,
            currency: order.currency,
            gross_cents:,
            tax_rate_bps: rule.fetch(:tax_rate_bps),
            jurisdiction_country: rule.fetch(:jurisdiction_country),
            jurisdiction_region: rule[:jurisdiction_region],
            tax_code: rule.fetch(:tax_code),
            calculation_version: CALCULATION_VERSION,
            line_snapshot:
          }.deep_stringify_keys.sort.to_h
        )
      )
    end

    def inclusive_taxable_base(gross_cents, rate_bps)
      return gross_cents if rate_bps.zero?

      divide_half_up(gross_cents * 10_000, 10_000 + rate_bps)
    end

    def divide_half_up(numerator, denominator)
      ((2 * numerator) + denominator) / (2 * denominator)
    end

    def integer_setting(key, default)
      Integer(SiteSetting.get(key, default.to_s).to_s, 10)
    rescue ArgumentError, TypeError
      default
    end

    def audit_state(snapshot)
      {
        tax_rate_bps: snapshot.tax_rate_bps,
        taxable_base_cents: snapshot.taxable_base_cents,
        tax_cents: snapshot.tax_cents,
        gross_cents: snapshot.gross_cents,
        currency: snapshot.currency,
        jurisdiction_country: snapshot.jurisdiction_country,
        jurisdiction_region: snapshot.jurisdiction_region,
        rounding_mode: snapshot.rounding_mode,
        retention_until: snapshot.retention_until.iso8601
      }
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
