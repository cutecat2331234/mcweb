# frozen_string_literal: true

module Website
  module RecoverableContent
    extend ActiveSupport::Concern

    IDEMPOTENCY_DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

    included do
      belongs_to :discarded_by, class_name: "User", optional: true
      belongs_to :purged_by, class_name: "User", optional: true

      default_scope { where(discarded_at: nil, purged_at: nil) }
      scope :with_lifecycle, -> { unscope(where: %i[discarded_at purged_at]) }
      scope :discarded_content, -> {
        with_lifecycle.where.not(discarded_at: nil).where(purged_at: nil)
      }
      scope :purged_tombstones, -> { with_lifecycle.where.not(purged_at: nil) }
      scope :purge_due, ->(at = Time.current) {
        discarded_content.where(purge_at: ..at)
      }

      validates :discard_reason, length: { maximum: 1_000 }, allow_nil: true
      validates :purge_reason, length: { maximum: 1_000 }, allow_nil: true
      validates :discard_reason, presence: true, if: :discarded?
      validates :purge_at, presence: true, if: :discarded?
      validates :purge_reason, presence: true, if: :purged?
      validates :discard_idempotency_key_digest,
        format: { with: IDEMPOTENCY_DIGEST_PATTERN },
        allow_nil: true
      validates :restore_idempotency_key_digest,
        format: { with: IDEMPOTENCY_DIGEST_PATTERN },
        allow_nil: true
      validates :purge_idempotency_key_digest,
        format: { with: IDEMPOTENCY_DIGEST_PATTERN },
        allow_nil: true
      validate :purged_tombstone_is_immutable, on: :update
      before_destroy :prevent_hard_delete
    end

    def discarded?
      discarded_at.present? && purged_at.nil?
    end

    def purged?
      purged_at.present?
    end

    def active_content?
      discarded_at.nil? && purged_at.nil?
    end

    private

    def purged_tombstone_is_immutable
      return unless attribute_in_database("purged_at").present?
      return unless has_changes_to_save?

      errors.add(:base, I18n.t("mcweb.validation_errors.website_content_tombstone_immutable"))
    end

    def prevent_hard_delete
      errors.add(:base, I18n.t("mcweb.validation_errors.website_content_recoverable_delete_required"))
      throw(:abort)
    end
  end
end
