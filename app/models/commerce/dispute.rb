# frozen_string_literal: true

module Commerce
  class Dispute < ApplicationRecord
    self.table_name = "store_disputes"

    include HasPublicId

    STATUSES = %w[
      open evidence_required evidence_submitted under_review
      won lost withdrawn closed
    ].freeze
    TERMINAL_STATUSES = %w[won lost withdrawn closed].freeze
    ACTIVE_EXPOSURE_STATUSES = %w[
      open evidence_required evidence_submitted under_review lost
    ].freeze
    RISK_LEVELS = %w[low medium high critical].freeze
    RIGHTS_STATUSES = %w[unchanged frozen revoked restored].freeze
    RESOLUTIONS = %w[won lost withdrawn accepted_loss].freeze
    RETENTION_PERIOD = 7.years
    CUSTOMER_PROVIDER_ID_PREFIX = "customer:".freeze
    CUSTOMER_EVIDENCE_STATUSES = %w[
      open evidence_required evidence_submitted under_review
    ].freeze
    CUSTOMER_WITHDRAW_STATUSES = %w[open evidence_required].freeze

    belongs_to :order,
               class_name: "Commerce::Order",
               foreign_key: :store_order_id
    belongs_to :payment_record,
               class_name: "Payments::Record"
    belongs_to :assigned_to, class_name: "User", optional: true
    belongs_to :accepted_loss_by, class_name: "User", optional: true
    belongs_to :closed_by, class_name: "User", optional: true
    belongs_to :customer_opened_by, class_name: "User", optional: true

    has_many :events,
             class_name: "Commerce::DisputeEvent",
             foreign_key: :store_dispute_id,
             dependent: :restrict_with_error
    has_many :evidence,
             class_name: "Commerce::DisputeEvidence",
             foreign_key: :store_dispute_id,
             dependent: :restrict_with_error
    has_many :rights_actions,
             class_name: "Commerce::DisputeRightsAction",
             foreign_key: :store_dispute_id,
             dependent: :restrict_with_error

    enum :status, STATUSES.index_with(&:itself), validate: true
    enum :risk_level, RISK_LEVELS.index_with(&:itself), validate: true, prefix: :risk
    enum :rights_status, RIGHTS_STATUSES.index_with(&:itself), validate: true, prefix: :rights

    validates :provider, :provider_dispute_id, :currency, presence: true
    validates :provider_dispute_id, uniqueness: { scope: :provider }
    validates :amount_cents,
              numericality: { only_integer: true, greater_than: 0 }
    validates :liability_cents, :offset_cents,
              numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :resolution, inclusion: { in: RESOLUTIONS }, allow_nil: true
    validate :payment_and_order_match
    validate :currency_matches_payment
    validate :amount_within_payment
    validate :amount_is_conserved
    validate :customer_origin_shape

    scope :recent, -> { order(created_at: :desc, id: :desc) }
    scope :active_exposure, lambda {
      where(status: ACTIVE_EXPOSURE_STATUSES)
        .or(
          where(
            status: "closed",
            resolution: %w[lost accepted_loss]
          )
        )
    }
    scope :due_soon, lambda {
      where(status: %w[open evidence_required])
        .where(evidence_due_at: Time.current..48.hours.from_now)
    }
    scope :customer_origin, -> { where.not(customer_opened_by_id: nil) }
    scope :customer_provider_pending, lambda {
      customer_origin.where("provider_dispute_id LIKE ?", "#{CUSTOMER_PROVIDER_ID_PREFIX}%")
    }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def evidence_overdue?
      evidence_due_at.present? &&
        evidence_due_at.past? &&
        %w[open evidence_required].include?(status)
    end

    def customer_origin?
      customer_opened_by_id.present?
    end

    def customer_provider_pending?
      customer_origin? && provider_dispute_id.to_s.start_with?(CUSTOMER_PROVIDER_ID_PREFIX)
    end

    def customer_evidence_allowed?
      CUSTOMER_EVIDENCE_STATUSES.include?(status)
    end

    def customer_withdrawable_by?(user)
      customer_opened_by_id == user&.id &&
        customer_provider_pending? &&
        CUSTOMER_WITHDRAW_STATUSES.include?(status)
    end

    def sensitive_reference
      payment_record.provider_payment_id.to_s.presence
    end

    def retention_blockers(at: Time.current)
      blockers = []
      blockers << "open_dispute" unless closed?
      blockers << "legal_hold" if legal_hold?
      blockers << "retention_period" if retention_until.present? && retention_until > at
      blockers
    end

    def purge_allowed?(at: Time.current)
      closed? && !legal_hold? && retention_until.present? && retention_until <= at
    end

    private

    def payment_and_order_match
      return if payment_record.nil? || order.nil?
      return if payment_record.store_order_id == order.id

      errors.add(:payment_record, I18n.t("mcweb.validation_errors.must_belong_to_the_dispute_order"))
    end

    def currency_matches_payment
      return if payment_record.nil? || currency.blank?
      return if currency.to_s.casecmp?(payment_record.currency.to_s)

      errors.add(:currency, I18n.t("mcweb.validation_errors.must_match_the_payment_currency"))
    end

    def amount_within_payment
      return if payment_record.nil? || amount_cents.blank?
      return if amount_cents <= payment_record.amount_cents

      errors.add(:amount_cents, I18n.t("mcweb.validation_errors.cannot_exceed_the_payment_amount"))
    end

    def amount_is_conserved
      return if amount_cents.blank? || liability_cents.blank? || offset_cents.blank?
      return if liability_cents + offset_cents == amount_cents

      errors.add(:base, I18n.t("mcweb.validation_errors.dispute_amount_is_not_conserved"))
    end

    def customer_origin_shape
      origin_values = [ customer_opened_by_id, customer_opened_at, customer_withdrawn_at ]
      return if origin_values.all?(&:blank?)
      return if customer_opened_by_id.present? && customer_opened_at.present?

      errors.add(:customer_opened_at, :invalid)
    end
  end
end
