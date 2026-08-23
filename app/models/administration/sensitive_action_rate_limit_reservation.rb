# frozen_string_literal: true

module Administration
  class SensitiveActionRateLimitReservation < ApplicationRecord
    include HasPublicId

    self.table_name = "sensitive_action_rate_limit_reservations"

    FROZEN_FIELDS = %w[
      public_id scope user_id user_counter_key ip_counter_key context_digest limit
      window_seconds expires_at
    ].freeze

    belongs_to :user

    enum :status, {
      pending: "pending",
      succeeded: "succeeded",
      failed: "failed"
    }, prefix: true, validate: true

    validates :scope, :user_counter_key, :ip_counter_key, presence: true
    validates :context_digest, format: { with: /\A[0-9a-f]{64}\z/ }
    validates :limit, :window_seconds, numericality: { only_integer: true, greater_than: 0 }
    validates :expires_at, presence: true
    validate :frozen_contract_is_immutable, on: :update
    validate :status_transition_is_valid, on: :update
    validate :settlement_timestamp_is_immutable, on: :update
    validate :settlement_timestamp_matches_status

    scope :active_at, ->(time) { where(status: "pending").where("expires_at > ?", time) }

    private

    def frozen_contract_is_immutable
      errors.add(:base, :immutable) if (changes_to_save.keys & FROZEN_FIELDS).any?
    end

    def status_transition_is_valid
      previous = status_in_database
      return if previous.blank? || previous == status
      return if previous == "pending" && status.in?(%w[succeeded failed])

      errors.add(:status, :invalid_transition)
    end

    def settlement_timestamp_is_immutable
      return unless attribute_in_database("settled_at").present? && will_save_change_to_settled_at?

      errors.add(:settled_at, :immutable)
    end

    def settlement_timestamp_matches_status
      if status_pending?
        errors.add(:settled_at, :invalid) if settled_at.present?
      elsif settled_at.blank?
        errors.add(:settled_at, :blank)
      end
    end
  end
end
