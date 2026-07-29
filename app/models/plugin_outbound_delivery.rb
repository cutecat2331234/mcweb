# frozen_string_literal: true

require "mcweb/plugins/manifest"

class PluginOutboundDelivery < ApplicationRecord
  KINDS = %w[notification mail webhook].freeze
  STATUSES = %w[queued processing retrying succeeded suppressed failed cancelled].freeze
  TERMINAL_STATUSES = %w[succeeded suppressed failed cancelled].freeze
  IDEMPOTENCY_PATTERN = /\A[a-zA-Z0-9][a-zA-Z0-9._:\/-]*\z/

  has_encrypted :destination, encrypted_attribute: :encrypted_destination
  has_encrypted :payload, type: :json, encrypted_attribute: :encrypted_payload
  has_encrypted :secret, encrypted_attribute: :encrypted_secret

  belongs_to :user, optional: true

  before_validation :assign_public_id, on: :create

  validates :public_id,
            presence: true,
            uniqueness: true,
            format: {
              with: /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
            }
  validates :owner_plugin_id,
            presence: true,
            length: { maximum: 191 },
            format: { with: Mcweb::Plugins::Manifest::ID_PATTERN }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key,
            presence: true,
            length: { maximum: 191 },
            format: { with: IDEMPOTENCY_PATTERN },
            uniqueness: { scope: %i[owner_plugin_id kind] }
  validates :payload_digest, format: { with: /\A[0-9a-f]{64}\z/ }
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :max_attempts, numericality: { only_integer: true, in: 1..10 }
  validates :last_error_code,
            allow_nil: true,
            length: { maximum: 64 },
            format: { with: /\A[a-z][a-z0-9_]*\z/ }
  validate :payload_must_be_mapping
  validate :kind_requirements

  scope :owned_by, ->(plugin_id) { where(owner_plugin_id: plugin_id.to_s) }
  scope :due, -> {
    where(status: %w[queued retrying])
      .where("next_attempt_at IS NULL OR next_attempt_at <= ?", Time.current)
  }

  def terminal?
    status.in?(TERMINAL_STATUSES)
  end

  private

  def assign_public_id
    self.public_id ||= SecureRandom.uuid
  end

  def payload_must_be_mapping
    errors.add(:payload, I18n.t("mcweb.validation_errors.must_be_a_mapping")) unless payload.is_a?(Hash)
  end

  def kind_requirements
    errors.add(:user, I18n.t("mcweb.validation_errors.is_required")) if kind.in?(%w[notification mail]) && user.blank?
    errors.add(:destination, I18n.t("mcweb.validation_errors.is_required")) if kind == "webhook" && destination.blank?
  end
end
