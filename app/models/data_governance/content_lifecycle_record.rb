# frozen_string_literal: true

module DataGovernance
  class ContentLifecycleRecord < ApplicationRecord
    self.table_name = "data_content_lifecycle_records"

    include HasPublicId

    STATUSES = %w[soft_deleted restored purged].freeze

    belongs_to :deleted_by, class_name: "User", optional: true
    belongs_to :restored_by, class_name: "User", optional: true
    belongs_to :purged_by, class_name: "User", optional: true

    enum :status, STATUSES.index_by(&:itself), validate: true, prefix: true

    validates :target_type, :target_id, :soft_deleted_at, :deletion_reason, presence: true
    validates :target_id, uniqueness: { scope: :target_type }
    validates :deletion_reason, :restoration_reason, :purge_reason,
              length: { maximum: 2_000 }, allow_blank: true
    validates :purge_attempts,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }

    scope :due_for_purge, lambda { |at = Time.current|
      status_soft_deleted
        .where.not(purge_after: nil)
        .where(purge_after: ..at)
    }
    scope :recent_first, -> { order(updated_at: :desc, id: :desc) }

    def target
      ContentRegistry.resolve(target_type:, target_id:)
    end

    def purge_due?(at: Time.current)
      status_soft_deleted? && purge_after.present? && purge_after <= at
    end
  end
end
