# frozen_string_literal: true

module Identity
  class DataExportBlobCleanupCursor < ApplicationRecord
    self.table_name = "identity_data_export_blob_cleanup_cursors"

    validates :name, presence: true, uniqueness: true
    validates :last_blob_id, :cycle_max_blob_id,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :last_blob_id_does_not_exceed_cycle

    private

    def last_blob_id_does_not_exceed_cycle
      return if last_blob_id.to_i.zero? && cycle_max_blob_id.to_i.zero?
      return if cycle_max_blob_id.to_i.positive? && last_blob_id.to_i <= cycle_max_blob_id.to_i

      errors.add(:last_blob_id, :invalid)
    end
  end
end
