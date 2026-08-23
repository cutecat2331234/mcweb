# frozen_string_literal: true

module Minecraft
  class PlayerAccessRule < ApplicationRecord
    include HasPublicId

    RULE_TYPES = %w[whitelist ban].freeze
    STATUSES = %w[pending_apply active pending_revoke revoked failed].freeze
    ACTIVE_STATUSES = %w[pending_apply active pending_revoke].freeze
    USERNAME_PATTERN = /\A[A-Za-z0-9_]{1,16}\z/

    belongs_to :server,
               class_name: "Minecraft::Server",
               foreign_key: :minecraft_server_id,
               inverse_of: :player_access_rules
    belongs_to :created_by, class_name: "User", optional: true
    belongs_to :revoked_by, class_name: "User", optional: true
    belongs_to :apply_task, class_name: "Minecraft::ConnectorTask", optional: true
    belongs_to :revoke_task, class_name: "Minecraft::ConnectorTask", optional: true

    enum :rule_type, RULE_TYPES.index_with(&:itself), validate: true, prefix: true
    enum :status, STATUSES.index_with(&:itself), validate: true

    validates :username, presence: true, format: { with: USERNAME_PATTERN }
    validates :reason, presence: true, length: { maximum: 500 }
    validates :revoke_reason, length: { maximum: 500 }, allow_nil: true
    validates :apply_idempotency_key_digest,
              presence: true,
              format: { with: /\A[0-9a-f]{64}\z/ },
              uniqueness: true
    validates :revoke_idempotency_key_digest,
              format: { with: /\A[0-9a-f]{64}\z/ },
              uniqueness: true,
              allow_nil: true
    validates :lock_version, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :reason_has_no_control_characters
    validate :revoke_reason_has_no_control_characters
    validate :expiry_is_after_creation
    validate :lifecycle_shape

    scope :recent, -> { order(id: :desc) }
    scope :effective, -> { where(status: ACTIVE_STATUSES) }
    scope :due_for_expiry, -> { active.where(expires_at: ..Time.current) }

    def target_key
      username.downcase
    end

    private

    def reason_has_no_control_characters
      errors.add(:reason, :invalid) if reason.to_s.match?(/[[:cntrl:]]/)
    end

    def revoke_reason_has_no_control_characters
      errors.add(:revoke_reason, :invalid) if revoke_reason.to_s.match?(/[[:cntrl:]]/)
    end

    def expiry_is_after_creation
      return if expires_at.blank?

      boundary = created_at || Time.current
      errors.add(:expires_at, :invalid) if expires_at <= boundary
    end

    def lifecycle_shape
      if active? && applied_at.blank?
        errors.add(:applied_at, :blank)
      elsif revoked? && (revoked_at.blank? || revoke_task_id.blank?)
        errors.add(:revoked_at, :blank)
      elsif failed? && failed_at.blank?
        errors.add(:failed_at, :blank)
      end
    end
  end
end
