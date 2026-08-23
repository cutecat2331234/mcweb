# frozen_string_literal: true

module Website
  class ThemeRevision < ApplicationRecord
    EVENT_TYPES = %w[create update activate deactivate restore legacy].freeze
    SNAPSHOT_KEYS = %w[name key tokens active].freeze
    DIGEST_PATTERN = /\A[0-9a-f]{64}\z/

    belongs_to :theme,
      class_name: "Website::Theme",
      foreign_key: :website_theme_id,
      inverse_of: :revisions
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :source_revision,
      class_name: "Website::ThemeRevision",
      optional: true

    validates :website_theme_id, presence: true
    validates :revision_number,
      numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :website_theme_id }
    validates :event_type, inclusion: { in: EVENT_TYPES }
    validates :reason, length: { maximum: 1_000 }, allow_nil: true
    validates :request_id_digest,
      format: { with: DIGEST_PATTERN },
      allow_nil: true,
      uniqueness: true
    validates :operation_digest,
      format: { with: DIGEST_PATTERN },
      allow_nil: true
    validates :source_lock_version,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :snapshot_contract
    validate :operation_contract

    before_update :prevent_mutation
    before_destroy :prevent_mutation

    scope :ordered, -> { order(revision_number: :desc, id: :desc) }

    private

    def prevent_mutation
      errors.add(:base, I18n.t("mcweb.services.errors.website_theme_revision_immutable"))
      throw(:abort)
    end

    def snapshot_contract
      value = snapshot.to_h.stringify_keys
      unless value.keys.sort == SNAPSHOT_KEYS.sort &&
          value["name"].is_a?(String) &&
          value["key"].is_a?(String) &&
          value["tokens"].is_a?(Hash) &&
          [ true, false ].include?(value["active"])
        errors.add(:snapshot, I18n.t("mcweb.services.errors.website_theme_snapshot_invalid"))
      end
    end

    def operation_contract
      if event_type == "restore"
        unless source_revision_id.present? && reason.present? &&
            request_id_digest.present? && operation_digest.present?
          errors.add(:base, I18n.t("mcweb.services.errors.website_theme_restore_contract_invalid"))
        end
      elsif source_revision_id.present? || request_id_digest.present? || operation_digest.present?
        errors.add(:base, I18n.t("mcweb.services.errors.website_theme_revision_contract_invalid"))
      end
    end
  end
end
