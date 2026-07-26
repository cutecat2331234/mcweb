# frozen_string_literal: true

module Payments
  class ReconciliationRetryableError < StandardError; end

  class DailyReconciliationJob < ApplicationJob
    queue_as :maintenance

    LOOKBACK_DAYS = 7
    RETRYABLE_CODES = %w[
      rate_limited
      provider_unavailable
      provider_error
      reconciliation_internal_error
    ].freeze

    retry_on Payments::ReconciliationRetryableError,
      wait: :polynomially_longer,
      attempts: 5

    def perform(
      date: nil,
      refresh: true,
      run_id: nil,
      config_binding: nil
    )
      unless date.present?
        lookback_dates.each do |reconciliation_date|
          self.class.perform_later(
            date: reconciliation_date,
            refresh: true
          )
        end
        return
      end

      arguments = { date: date, refresh: refresh }
      if run_id.present? || config_binding.present?
        arguments[:reserved_run_id] = run_id
        arguments[:expected_config_binding] = config_binding
      end

      result = Payments::ReconcileDay.call(**arguments)
      return if result.success? || !result.code.in?(RETRYABLE_CODES)

      raise Payments::ReconciliationRetryableError, result.code
    end

    private

    def lookback_dates
      today = Time.now.utc.to_date
      (1..LOOKBACK_DAYS).map { |days_ago| (today - days_ago).iso8601 }
    end
  end
end
