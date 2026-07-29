# frozen_string_literal: true

require "mcweb/plugins/manifest"

class PluginJobRun < ApplicationRecord
  STATUSES = %w[queued running retrying succeeded failed paused cancelled].freeze
  TERMINAL_STATUSES = %w[succeeded failed cancelled].freeze
  MUTABLE_COLUMNS = %w[
    status attempts scheduled_at enqueued_at started_at finished_at lease_expires_at
    active_job_id recovery_claimed_at last_error_code last_enqueue_error_code updated_at
  ].freeze
  JOB_KEY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z/
  IDEMPOTENCY_KEY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._:\/-]*\z/

  has_encrypted :arguments, type: :json, encrypted_attribute: :encrypted_arguments

  before_validation :assign_public_id, on: :create

  validates :public_id,
    presence: true,
    uniqueness: true,
    format: { with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/ }
  validates :owner_plugin_id,
    presence: true,
    length: { maximum: 191 },
    format: { with: Mcweb::Plugins::Manifest::ID_PATTERN }
  validates :plugin_version, presence: true, length: { maximum: 128 }
  validates :job_key,
    presence: true,
    length: { maximum: 191 },
    format: { with: JOB_KEY_PATTERN }
  validates :contribution_schema_version,
    presence: true,
    length: { maximum: 32 },
    format: { with: /\A[1-9]\d{0,8}\z/ }
  validates :declaration_digest, :payload_digest,
    presence: true,
    format: { with: /\A[0-9a-f]{64}\z/ }
  validates :payload_digest_version,
    numericality: { only_integer: true, equal_to: 2 }
  validates :idempotency_key,
    presence: true,
    length: { maximum: 191 },
    format: { with: IDEMPOTENCY_KEY_PATTERN }
  validates :idempotency_key, uniqueness: { scope: %i[owner_plugin_id job_key] }
  validates :status, inclusion: { in: STATUSES }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { only_integer: true, in: 1..10 }
  validates :retry_wait_seconds, numericality: { only_integer: true, in: 0..86_400 }
  validates :lease_seconds, numericality: { only_integer: true, in: 30..3_600 }
  validates :requested_wait_seconds,
    numericality: { only_integer: true, in: 0..31_536_000 }
  validates :scheduled_at, presence: true
  validates :last_error_code,
    length: { maximum: 64 },
    format: { with: /\A[a-z][a-z0-9_]*\z/ },
    allow_nil: true
  validates :last_enqueue_error_code,
    length: { maximum: 64 },
    format: { with: /\A[a-z][a-z0-9_]*\z/ },
    allow_nil: true
  validate :arguments_must_be_mapping, if: :validate_arguments_payload?
  validate :immutable_identity, on: :update

  scope :owned_by, ->(plugin_id) { where(owner_plugin_id: plugin_id.to_s) }
  scope :newest_first, -> { order(id: :desc) }

  def terminal?
    status.in?(TERMINAL_STATUSES)
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def arguments_must_be_mapping
    errors.add(:arguments, I18n.t("mcweb.validation_errors.must_be_a_mapping")) unless arguments.is_a?(Hash)
  end

  def validate_arguments_payload?
    new_record? || will_save_change_to_encrypted_arguments?
  end

  def immutable_identity
    forbidden = changes_to_save.keys - MUTABLE_COLUMNS
    return if forbidden.empty?

    errors.add(:base, I18n.t("mcweb.validation_errors.plugin_job_ownership_and_payload_are_immutable"))
  end
end
