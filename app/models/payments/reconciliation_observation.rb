# frozen_string_literal: true

module Payments
  class ReconciliationObservation < ApplicationRecord
    SUBJECT_TYPES = %w[payment refund].freeze

    belongs_to :run,
      class_name: "Payments::ReconciliationRun",
      inverse_of: :observations

    validates :subject_type, inclusion: { in: SUBJECT_TYPES }
    validates :reference_digest,
      format: { with: /\A\h{64}\z/ },
      uniqueness: { scope: %i[run_id subject_type] }
  end
end
