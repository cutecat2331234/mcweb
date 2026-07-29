# frozen_string_literal: true

module Commerce
  class FinanceDocumentQuery
    FILTER_KEYS = %w[
      from to channel currency status document_kind tax_country tax_region tax_rate_bps
    ].freeze

    attr_reader :filters

    def initialize(filters = {})
      @filters = self.class.normalize(filters)
    end

    def relation
      scope = FinanceDocument.includes(:order, :refund, :tax_snapshot)
      scope = scope.where("store_finance_documents.issued_at >= ?", Time.iso8601(filters["from"])) if filters["from"]
      scope = scope.where("store_finance_documents.issued_at <= ?", Time.iso8601(filters["to"])) if filters["to"]
      scope = scope.where(channel: filters["channel"]) if filters["channel"]
      scope = scope.where(currency: filters["currency"]) if filters["currency"]
      scope = scope.where(status: filters["status"]) if filters["status"]
      scope = scope.where(document_kind: filters["document_kind"]) if filters["document_kind"]

      if tax_filters?
        scope = scope.joins(:tax_snapshot)
        scope = scope.where(
          store_finance_tax_snapshots: { jurisdiction_country: filters["tax_country"] }
        ) if filters["tax_country"]
        scope = scope.where(
          store_finance_tax_snapshots: { jurisdiction_region: filters["tax_region"] }
        ) if filters["tax_region"]
        scope = scope.where(
          store_finance_tax_snapshots: { tax_rate_bps: filters["tax_rate_bps"] }
        ) if filters["tax_rate_bps"]
      end

      scope.recent_first
    end

    def summary
      base = relation.reorder(nil)
      gross_by_currency = base.group(:currency).sum(:gross_amount_cents)
      tax_by_currency = base.group(:currency).sum(:tax_amount_cents)
      currencies = (gross_by_currency.keys | tax_by_currency.keys).compact.sort

      {
        documents: base.count,
        invoices: base.where(document_kind: "invoice").count,
        refund_receipts: base.where(document_kind: "refund_receipt").count,
        totals_by_currency: currencies.map do |currency|
          {
            currency:,
            gross_cents: gross_by_currency.fetch(currency, 0),
            tax_cents: tax_by_currency.fetch(currency, 0)
          }
        end
      }
    end

    def options
      {
        channels: FinanceDocument.distinct.order(:channel).pluck(:channel),
        currencies: FinanceDocument.distinct.order(:currency).pluck(:currency),
        tax_countries: FinanceTaxSnapshot.distinct.order(:jurisdiction_country).pluck(:jurisdiction_country),
        tax_regions: FinanceTaxSnapshot.where.not(jurisdiction_region: [ nil, "" ])
          .distinct
          .order(:jurisdiction_region)
          .pluck(:jurisdiction_region),
        tax_rates: FinanceTaxSnapshot.distinct.order(:tax_rate_bps).pluck(:tax_rate_bps)
      }
    end

    def self.normalize(raw_filters)
      source = raw_filters.to_h.stringify_keys.slice(*FILTER_KEYS)
      normalized = source.transform_values { |value| value.to_s.strip.presence }.compact
      normalized["from"] = normalize_time(normalized["from"], end_of_day: false)
      normalized["to"] = normalize_time(normalized["to"], end_of_day: true)
      normalized["tax_rate_bps"] = normalize_integer(normalized["tax_rate_bps"])
      normalized.compact
    end

    def self.normalize_time(value, end_of_day:)
      return if value.blank?

      if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        date = Date.iso8601(value)
        time = end_of_day ? date.end_of_day : date.beginning_of_day
        return time.in_time_zone.iso8601
      end

      Time.iso8601(value).iso8601
    rescue ArgumentError
      nil
    end

    def self.normalize_integer(value)
      return if value.blank?

      Integer(value, 10)
    rescue ArgumentError, TypeError
      nil
    end

    private

    def tax_filters?
      filters.values_at("tax_country", "tax_region", "tax_rate_bps").any?(&:present?)
    end
  end
end
