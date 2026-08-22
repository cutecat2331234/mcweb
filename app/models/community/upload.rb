# frozen_string_literal: true

module Community
  class Upload < ApplicationRecord
    self.table_name = "forum_uploads"

    KINDS = %w[inline_image post_attachment secure_evidence_attachment].freeze
    STATUSES = %w[reserved stored linked cleanup_pending cleanup_failed cleaned].freeze
    SCAN_STATUSES = %w[pending clean infected error].freeze
    MANUAL_REVIEW_STATUSES = %w[none released revoked].freeze
    QUOTA_STATUSES = (STATUSES - [ "cleaned" ]).freeze
    CLEANUP_STATUSES = %w[reserved stored linked cleanup_pending cleanup_failed].freeze

    belongs_to :user
    belongs_to :blob,
      class_name: "ActiveStorage::Blob",
      foreign_key: :active_storage_blob_id,
      optional: true
    belongs_to :post_attachment,
      class_name: "Community::PostAttachment",
      foreign_key: :forum_post_attachment_id,
      optional: true,
      inverse_of: :upload_record
    belongs_to :post,
      class_name: "Community::Post",
      foreign_key: :forum_post_id,
      optional: true,
      inverse_of: :inline_uploads
    belongs_to :manual_reviewed_by,
      class_name: "User",
      optional: true
    belongs_to :manual_review_revoked_by,
      class_name: "User",
      optional: true
    belongs_to :secure_evidence_attachment,
      class_name: "SecureEvidence::Attachment",
      optional: true,
      inverse_of: :upload_record

    enum :kind, KINDS.index_by(&:itself), validate: true, prefix: true
    enum :status, STATUSES.index_by(&:itself), validate: true, prefix: true
    enum :scan_status, SCAN_STATUSES.index_by(&:itself), validate: true, prefix: true
    enum :manual_review_status,
      MANUAL_REVIEW_STATUSES.index_by(&:itself),
      validate: true,
      prefix: true

    validates :public_id, presence: true, uniqueness: true
    validates :byte_size, numericality: { only_integer: true, greater_than: 0 }
    validates :cleanup_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :scan_attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :manual_review_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :counted_toward_quota, -> { where(status: QUOTA_STATUSES) }
    scope :cleanup_due, ->(at = Time.current) {
      where(status: CLEANUP_STATUSES)
        .where("expires_at <= :at OR (status = 'cleanup_pending' AND cleanup_started_at <= :stale)", {
          at: at,
          stale: at - 30.minutes
        })
    }
    scope :scan_due, ->(at = Time.current) {
      due = where(kind: %w[post_attachment secure_evidence_attachment], scan_status: %w[pending error])
        .where.not(status: %w[cleanup_pending cleanup_failed cleaned])
        .where(
          "next_scan_at <= :at OR " \
          "(scan_status = 'pending' AND scan_started_at <= :stale)",
          at: at,
          stale: at - 15.minutes
        )

      if Mcweb::DeveloperMode.allow?(:skip_attachment_malware_scan)
        due
      else
        due.or(
          where(
            kind: %w[post_attachment secure_evidence_attachment],
            status: STATUSES - %w[cleanup_pending cleanup_failed cleaned],
            scan_status: "clean",
            scanner: "developer_mode",
            scan_result_code: "dev_bypassed"
          )
        )
      end
    }

    def self.generate_public_id
      "upl_#{SecureRandom.urlsafe_base64(24)}"
    end

    def stored!(blob:, expires_at:)
      scan_attributes =
        if kind_inline_image?
          {
            scan_status: "clean",
            scanner: "image_inspector",
            scan_result_code: "decoded_image",
            scanned_at: Time.current,
            next_scan_at: nil
          }
        else
          {
            scan_status: "pending",
            next_scan_at: Time.current
          }
        end

      update!(
        blob: blob,
        status: "stored",
        expires_at: expires_at,
        cleanup_started_at: nil,
        cleanup_error_code: nil,
        cleanup_error_message: nil,
        **scan_attributes
      )
    end

    def scan_clean?
      scan_status_clean? &&
        active_storage_blob_id.present? &&
        (
          !developer_mode_scan_bypassed? ||
          Mcweb::DeveloperMode.allow?(:skip_attachment_malware_scan)
        )
    end

    def developer_mode_scan_bypassed?
      scanner == "developer_mode" && scan_result_code == "dev_bypassed"
    end

    def scan_quarantined?
      scan_status_infected? || (scan_status_error? && quarantined_at.present?)
    end

    def request_cleanup!(error: nil)
      attributes = {
        status: "cleanup_failed",
        expires_at: Time.current,
        cleanup_started_at: nil
      }
      if error
        attributes[:cleanup_error_code] = error.class.name.to_s.first(120)
        attributes[:cleanup_error_message] = error.message.to_s.first(500)
      end
      update!(attributes)
    end

    def schedule_cleanup!(at: Time.current)
      update!(
        status: "cleanup_pending",
        expires_at: at,
        cleanup_started_at: nil,
        cleanup_error_code: nil,
        cleanup_error_message: nil
      )
    end
  end
end
