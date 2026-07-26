# frozen_string_literal: true

module Payments
  class LatePaymentCasesQuery
    MAX_QUERY_LENGTH = 100

    attr_reader :filters

    def initialize(status: nil, reason: nil, provider: nil, query: nil)
      @status = normalized_filter(status, Payments::LatePaymentCase.statuses.keys)
      @reason = normalized_filter(reason, Payments::LatePaymentCase::REASONS)
      @provider = provider.to_s.strip.first(80).presence
      @query = query.to_s.strip.first(MAX_QUERY_LENGTH).presence
      @filters = {
        status: @status,
        reason: @reason,
        provider: @provider,
        q: @query
      }
    end

    def relation
      scope = Payments::LatePaymentCase
        .joins(:order, :payment_record, :webhook_event)
        .includes(:order, :payment_record, :webhook_event, :acknowledged_by)
      scope = scope.where(status: @status) if @status
      scope = scope.where(reason: @reason) if @reason
      scope = scope.where(provider: @provider) if @provider
      scope = apply_query(scope)
      scope.order(
        Arel.sql("CASE payment_late_payment_cases.status WHEN 'open' THEN 0 ELSE 1 END"),
        created_at: :desc
      )
    end

    def summary
      counts = Payments::LatePaymentCase.group(:status).count
      {
        total: counts.values.sum,
        open: counts["open"].to_i,
        acknowledged: counts["acknowledged"].to_i
      }
    end

    def filter_options
      {
        statuses: Payments::LatePaymentCase.statuses.keys,
        reasons: Payments::LatePaymentCase::REASONS,
        providers: Payments::LatePaymentCase.distinct.order(:provider).pluck(:provider)
      }
    end

    private

    def normalized_filter(value, allowlist)
      text = value.to_s
      text if text.in?(allowlist)
    end

    def apply_query(scope)
      return scope unless @query

      scope.where(
        <<~SQL.squish,
          store_orders.order_number ILIKE :needle
          OR payment_records.provider_payment_id ILIKE :needle
          OR payment_webhook_events.event_id ILIKE :needle
          OR CAST(payment_late_payment_cases.id AS TEXT) = :exact
        SQL
        needle: "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%",
        exact: @query
      )
    end
  end
end
