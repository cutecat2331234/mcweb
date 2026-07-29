# frozen_string_literal: true

module Commerce
  class FinanceDocumentEvent < ApplicationRecord
    self.table_name = "store_finance_document_events"

    belongs_to :finance_document,
      class_name: "Commerce::FinanceDocument",
      foreign_key: :store_finance_document_id
    belongs_to :actor, class_name: "User", optional: true

    validates :event_type, inclusion: { in: %w[issued superseded voided] }
    validates :request_id, uniqueness: true, allow_nil: true

    scope :chronological, -> { order(:created_at, :id) }

    def readonly?
      persisted?
    end
  end
end
