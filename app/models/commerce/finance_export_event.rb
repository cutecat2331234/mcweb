# frozen_string_literal: true

module Commerce
  class FinanceExportEvent < ApplicationRecord
    self.table_name = "store_finance_export_events"

    belongs_to :finance_export,
      class_name: "Commerce::FinanceExport",
      foreign_key: :store_finance_export_id
    belongs_to :actor, class_name: "User", optional: true

    validates :status, inclusion: { in: %w[queued running completed failed expired revoked] }
    validates :progress_percent,
      numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

    scope :chronological, -> { order(:created_at, :id) }

    def readonly?
      persisted?
    end
  end
end
