# frozen_string_literal: true

module Commerce
  class FinanceExport < ApplicationRecord
    include HasPublicId

    self.table_name = "store_finance_exports"

    belongs_to :requested_by, class_name: "User"
    has_many :events,
      class_name: "Commerce::FinanceExportEvent",
      foreign_key: :store_finance_export_id,
      dependent: :restrict_with_error
    has_one_attached :file

    enum :status, {
      queued: "queued",
      running: "running",
      completed: "completed",
      failed: "failed",
      expired: "expired",
      revoked: "revoked"
    }, validate: true

    validates :idempotency_key, presence: true, uniqueness: { scope: :requested_by_id }
    validates :filters_digest, :requested_at, :retention_until, presence: true
    validates :format, inclusion: { in: %w[csv] }
    validates :progress_percent,
      numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }
    validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validate :request_contract_is_immutable, on: :update
    validate :status_transition_is_allowed, on: :update

    before_destroy { throw(:abort) }

    scope :recent_first, -> { order(requested_at: :desc, id: :desc) }

    def downloadable?
      completed? && revoked_at.nil? && expires_at.present? && expires_at.future? && file.attached?
    end

    private

    def request_contract_is_immutable
      immutable = %w[requested_by_id idempotency_key filters_digest filters format requested_at retention_until]
      return if (changes_to_save.keys & immutable).empty?

      errors.add(:base, I18n.t("mcweb.validation_errors.finance_export_request_contract_is_immutable"))
    end

    def status_transition_is_allowed
      return unless will_save_change_to_status?

      from, to = status_change_to_be_saved
      allowed = {
        "queued" => %w[running revoked],
        "running" => %w[completed failed revoked],
        "completed" => %w[expired revoked],
        "failed" => %w[queued revoked],
        "expired" => %w[revoked],
        "revoked" => []
      }
      return if allowed.fetch(from, []).include?(to)

      errors.add(:status, I18n.t("mcweb.validation_errors.transition_is_not_allowed"))
    end
  end
end
