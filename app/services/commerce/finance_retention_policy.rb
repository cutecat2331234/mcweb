# frozen_string_literal: true

module Commerce
  class FinanceRetentionPolicy
    SOURCE_RECORD_RETENTION = 7 * 365.days
    DOCUMENT_RETENTION = 7 * 365.days
    EXPORT_METADATA_RETENTION = 1.year
    EXPORT_FILE_RETENTION = 72.hours

    RULES = {
      orders: { record_days: 7 * 365, deletion: "retain_until_expiry" },
      payments: { record_days: 7 * 365, deletion: "retain_until_expiry" },
      refunds: { record_days: 7 * 365, deletion: "retain_until_expiry" },
      invoices: { record_days: 7 * 365, deletion: "immutable_until_expiry" },
      refund_receipts: { record_days: 7 * 365, deletion: "immutable_until_expiry" },
      export_metadata: { record_days: 365, deletion: "retain_audit_metadata" },
      export_files: { file_hours: 72, deletion: "purge_after_expiry" }
    }.freeze

    def self.source_retention_until(from: Time.current)
      from + SOURCE_RECORD_RETENTION
    end

    def self.document_retention_until(from: Time.current)
      from + DOCUMENT_RETENTION
    end

    def self.export_metadata_retention_until(from: Time.current)
      from + EXPORT_METADATA_RETENTION
    end

    def self.export_file_expires_at(from: Time.current)
      from + EXPORT_FILE_RETENTION
    end
  end
end
