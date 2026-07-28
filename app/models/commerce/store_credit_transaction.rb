# frozen_string_literal: true

module Commerce
  class StoreCreditTransaction < ApplicationRecord
    self.table_name = "store_credit_transactions"

    REQUEST_ID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    SHA256_FORMAT = /\A[0-9a-f]{64}\z/

    belongs_to :user
    belongs_to :order, class_name: "Commerce::Order", foreign_key: :store_order_id, optional: true
    belongs_to :actor, class_name: "User", optional: true

    before_validation :normalize_request_id

    validates :amount_cents, presence: true, numericality: { other_than: 0 }
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
    validate :adjustment_metadata_is_complete
    validate :adjustment_balance_matches_amount

    scope :recent, -> { order(created_at: :desc) }

    private

    def normalize_request_id
      self.request_id = request_id.to_s.strip.downcase.presence
    end

    def adjustment_metadata_is_complete
      values = [
        request_id,
        request_fingerprint,
        authorization_digest,
        balance_before_cents,
        balance_after_cents
      ]
      return if values.all?(&:nil?) || values.none?(&:nil?)

      errors.add(:request_id, :invalid)
    end

    def adjustment_balance_matches_amount
      return if balance_before_cents.nil? || balance_after_cents.nil?
      return if balance_before_cents + amount_cents.to_i == balance_after_cents

      errors.add(:balance_after_cents, :invalid)
    end
  end
end
