# frozen_string_literal: true

module Identity
  class DataExport < ApplicationRecord
    self.table_name = "identity_data_exports"

    include HasPublicId

    belongs_to :user
    has_one_attached :archive

    enum :status, {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      revoked: "revoked",
      expired: "expired"
    }, validate: true

    validates :idempotency_key, presence: true, uniqueness: { scope: :user_id }
    validates :format, inclusion: { in: %w[zip] }

    scope :recent_first, -> { order(requested_at: :desc, id: :desc) }

    def downloadable?
      completed? && revoked_at.nil? && expires_at.present? && expires_at.future? && archive.attached?
    end

    def mark_expired_if_needed!
      return false unless completed? && expires_at.present? && expires_at <= Time.current

      update!(status: :expired)
      archive.purge_later if archive.attached?
      true
    end
  end
end
