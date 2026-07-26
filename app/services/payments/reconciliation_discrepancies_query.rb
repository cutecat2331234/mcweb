# frozen_string_literal: true

module Payments
  class ReconciliationDiscrepanciesQuery
    MAX_QUERY_LENGTH = 100

    attr_reader :filters

    def initialize(status: nil, kind: nil, subject_type: nil, provider: nil, mode: nil, query: nil)
      @status = normalized_filter(status, Payments::ReconciliationDiscrepancy::STATUSES)
      @kind = normalized_filter(kind, Payments::ReconciliationDiscrepancy::KINDS)
      @subject_type = normalized_filter(
        subject_type,
        Payments::ReconciliationDiscrepancy::SUBJECT_TYPES
      )
      @provider = safe_token(provider, max_length: 32)
      @mode = normalized_filter(mode, Payments::ReconciliationRun::MODES)
      @query = query.to_s.strip.first(MAX_QUERY_LENGTH).presence
      @filters = {
        status: @status,
        kind: @kind,
        subject_type: @subject_type,
        provider: @provider,
        mode: @mode,
        q: @query
      }
    end

    def relation
      scope = Payments::ReconciliationDiscrepancy
        .left_joins(:order)
        .includes(:run, :order, :payment_record, :refund, :reviewed_by)
      scope = scope.where(status: @status) if @status
      scope = scope.where(kind: @kind) if @kind
      scope = scope.where(subject_type: @subject_type) if @subject_type
      scope = scope.where(provider: @provider) if @provider
      scope = scope.where(mode: @mode) if @mode
      scope = apply_query(scope)
      scope.order(
        Arel.sql(
          "CASE payment_reconciliation_discrepancies.status " \
            "WHEN 'open' THEN 0 WHEN 'acknowledged' THEN 1 ELSE 2 END"
        ),
        created_at: :desc
      )
    end

    def summary
      counts = Payments::ReconciliationDiscrepancy.group(:status).count
      {
        total: counts.values.sum,
        open: counts["open"].to_i,
        acknowledged: counts["acknowledged"].to_i,
        ignored: counts["ignored"].to_i,
        resolved: counts["resolved"].to_i
      }
    end

    def filter_options
      {
        statuses: Payments::ReconciliationDiscrepancy::STATUSES,
        kinds: Payments::ReconciliationDiscrepancy::KINDS,
        subject_types: Payments::ReconciliationDiscrepancy::SUBJECT_TYPES,
        providers: Payments::ReconciliationDiscrepancy.distinct.order(:provider).pluck(:provider),
        modes: Payments::ReconciliationRun::MODES
      }
    end

    private

    def normalized_filter(value, allowlist)
      text = value.to_s
      text if text.in?(allowlist)
    end

    def safe_token(value, max_length:)
      text = value.to_s.strip
      return if text.blank? || text.length > max_length
      return unless text.match?(/\A[a-z0-9_.:-]+\z/i)

      text
    end

    def apply_query(scope)
      return scope unless @query

      scope.where(
        <<~SQL.squish,
          payment_reconciliation_discrepancies.public_id ILIKE :needle
          OR store_orders.order_number ILIKE :needle
          OR CAST(payment_reconciliation_discrepancies.id AS TEXT) = :exact
        SQL
        needle: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%",
        exact: @query
      )
    end
  end
end
