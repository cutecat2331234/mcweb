# frozen_string_literal: true

module Payments
  class ReconciliationRun < ApplicationRecord
    STATUSES = %w[pending running completed failed skipped].freeze
    PHASES = %w[payments refunds local_checks completed].freeze
    MODES = %w[test live].freeze
    LEASE_TIMEOUT = 15.minutes

    has_many :observations,
      class_name: "Payments::ReconciliationObservation",
      foreign_key: :run_id,
      inverse_of: :run,
      dependent: :delete_all
    has_many :discrepancies,
      class_name: "Payments::ReconciliationDiscrepancy",
      foreign_key: :run_id,
      inverse_of: :run,
      dependent: :restrict_with_error

    enum :status, STATUSES.index_with(&:itself), validate: true
    enum :phase, PHASES.index_with(&:itself), validate: true, prefix: true

    validates :provider, presence: true
    validates :mode, inclusion: { in: MODES }
    validates :window_start, :window_end, presence: true
    validates :attempt_count,
      :refresh_count,
      :payments_checked,
      :refunds_checked,
      :discrepancies_count,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :valid_window

    scope :recent, -> { order(window_start: :desc, created_at: :desc) }

    def lease_active?(at: Time.current)
      running? &&
        processing_token.present? &&
        last_heartbeat_at.present? &&
        last_heartbeat_at >= at - LEASE_TIMEOUT
    end

    private

    def valid_window
      return unless window_start && window_end

      errors.add(:window_end, "must be after the start") unless window_end > window_start
    end
  end
end
