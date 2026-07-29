# frozen_string_literal: true

require "csv"
require "digest"
require "stringio"

module Commerce
  class FinanceCsvExport < ApplicationService
    MAX_ROWS = 100_000
    HEADERS = %w[
      document_number version document_kind status issued_at channel currency
      net_amount_cents tax_amount_cents gross_amount_cents tax_rate_bps tax_code
      tax_country tax_region order_number order_public_id refund_id retention_until
    ].freeze

    def initialize(filters:)
      @query = FinanceDocumentQuery.new(filters)
    end

    def call
      relation = @query.relation
      row_count = relation.count
      return failure("finance_export_too_large") if row_count > MAX_ROWS

      csv = CSV.generate(headers: true) do |output|
        output << HEADERS
        relation.find_each do |document|
          output << row(document).map { |value| safe_cell(value) }
        end
      end
      bytes = csv.b
      ServiceResult.success(
        io: StringIO.new(bytes),
        row_count:,
        file_sha256: Digest::SHA256.hexdigest(bytes)
      )
    rescue StandardError => e
      Rails.logger.error("finance export generation failed: #{e.class}")
      failure("finance_export_generation_failed")
    end

    private

    def row(document)
      snapshot = document.tax_snapshot
      [
        document.document_number,
        document.version,
        document.document_kind,
        document.status,
        document.issued_at.iso8601,
        document.channel,
        document.currency,
        document.net_amount_cents,
        document.tax_amount_cents,
        document.gross_amount_cents,
        snapshot.tax_rate_bps,
        snapshot.tax_code,
        snapshot.jurisdiction_country,
        snapshot.jurisdiction_region,
        document.order.order_number,
        document.order.public_id,
        document.store_refund_id,
        document.retention_until.iso8601
      ]
    end

    def safe_cell(value)
      return value unless value.is_a?(String)
      return value unless value.match?(/\A\s*[=+\-@]/)

      "'#{value}"
    end

    def failure(code)
      ServiceResult.failure(error: code, code:)
    end
  end
end
