# frozen_string_literal: true

module Commerce
  class StoreCreditTransaction < ApplicationRecord
    self.table_name = "store_credit_transactions"

    REQUEST_ID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    SHA256_FORMAT = /\A[0-9a-f]{64}\z/
    LEGACY_LEDGER_VERSION = 1
    CURRENT_LEDGER_VERSION = 2

    belongs_to :user
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id, optional: true
    belongs_to :actor, class_name: "User", optional: true

    before_validation :normalize_request_id
    before_destroy :prevent_ledger_destroy

    validates :amount_cents, presence: true, numericality: { other_than: 0 }
    validates :ledger_version,
      presence: true,
      inclusion: { in: [ LEGACY_LEDGER_VERSION, CURRENT_LEDGER_VERSION ] }
    validates :request_id,
      format: { with: REQUEST_ID_FORMAT },
      uniqueness: true,
      allow_nil: true
    validates :request_fingerprint, :authorization_digest,
      format: { with: SHA256_FORMAT },
      allow_nil: true
    validates :balance_before_cents, :balance_after_cents,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 },
      allow_nil: true
    validate :request_metadata_is_complete
    validate :balance_snapshot_is_complete
    validate :adjustment_balance_matches_amount
    validate :legacy_contract_is_not_assignable, on: :create
    validate :prevent_ledger_update, on: :update

    scope :recent, -> { order(created_at: :desc) }

    private

    def normalize_request_id
      self.request_id = request_id.to_s.strip.downcase.presence
    end

    def request_metadata_is_complete
      values = [ request_id, request_fingerprint, authorization_digest ]
      return if values.all?(&:nil?) || values.none?(&:nil?)

      errors.add(:request_id, :invalid)
    end

    def balance_snapshot_is_complete
      values = [ balance_before_cents, balance_after_cents ]
      return if ledger_version == LEGACY_LEDGER_VERSION && values.all?(&:nil?)
      return if ledger_version == CURRENT_LEDGER_VERSION && values.none?(&:nil?)

      errors.add(:balance_before_cents, :invalid)
    end

    def adjustment_balance_matches_amount
      return if balance_before_cents.nil? || balance_after_cents.nil?
      return if balance_before_cents + amount_cents.to_i == balance_after_cents

      errors.add(:balance_after_cents, :invalid)
    end

    def legacy_contract_is_not_assignable
      return unless ledger_version == LEGACY_LEDGER_VERSION

      errors.add(:ledger_version, :invalid)
    end

    def prevent_ledger_update
      errors.add(:base, :immutable)
    end

    def prevent_ledger_destroy
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
