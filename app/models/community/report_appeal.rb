# frozen_string_literal: true

module Community
  class ReportAppeal < ApplicationRecord
    self.table_name = "forum_report_appeals"

    include HasPublicId

    APPELLANT_ROLES = %w[reporter affected_subject].freeze
    STATUSES = %w[draft submitted under_review upheld overturned cancelled].freeze
    ACTIVE_STATUSES = %w[draft submitted under_review].freeze
    REVIEW_QUEUE_STATUSES = %w[submitted under_review].freeze
    TERMINAL_STATUSES = %w[upheld overturned cancelled].freeze
    PUBLIC_OUTCOME_CODES = %w[upheld overturned cancelled].freeze
    MAX_REASON_LENGTH = 5_000
    MAX_INTERNAL_NOTE_LENGTH = 5_000
    DRAFT_TTL = 48.hours

    belongs_to :report,
      class_name: "Community::Report",
      foreign_key: :forum_report_id,
      inverse_of: :appeals
    belongs_to :appellant, class_name: "User"
    belongs_to :reviewer, class_name: "User", optional: true
    has_many :events,
      class_name: "Community::ReportAppealEvent",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :appeal,
      dependent: :restrict_with_error
    has_many :evidence_links,
      class_name: "Community::ReportAppealAttachment",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :appeal,
      dependent: :restrict_with_error
    has_many :secure_evidence_attachments,
      through: :evidence_links,
      source: :attachment
    has_one :outcome_delivery,
      class_name: "Community::ReportAppealOutcomeDelivery",
      foreign_key: :forum_report_appeal_id,
      inverse_of: :appeal,
      dependent: :restrict_with_error

    enum :status, STATUSES.index_with(&:itself), validate: true
    enum :appellant_role, APPELLANT_ROLES.index_with(&:itself), validate: true, prefix: true

    validates :public_id, length: { in: 12..64 }
    validates :reason,
      presence: true,
      length: { maximum: MAX_REASON_LENGTH },
      unless: -> { draft? || (cancelled? && submitted_at.nil?) }
    validates :internal_note,
      length: { maximum: MAX_INTERNAL_NOTE_LENGTH },
      allow_nil: true
    validates :public_outcome_code,
      inclusion: { in: PUBLIC_OUTCOME_CODES },
      allow_nil: true
    validates :draft_idempotency_key_digest,
      :draft_request_fingerprint,
      presence: true,
      format: { with: /\A[0-9a-f]{64}\z/ }
    validates :submit_idempotency_key_digest,
      :submit_request_fingerprint,
      :cancel_idempotency_key_digest,
      :cancel_request_fingerprint,
      :decision_idempotency_key_digest,
      :decision_request_fingerprint,
      format: { with: /\A[0-9a-f]{64}\z/ },
      allow_nil: true
    validate :role_matches_report
    validate :state_shape
    validate :transition_is_valid, on: :update
    validate :mutation_identity_is_write_once, on: :update

    attr_readonly :public_id,
      :forum_report_id,
      :appellant_id,
      :appellant_role,
      :draft_idempotency_key_digest,
      :draft_request_fingerprint,
      :created_at

    before_update :prevent_terminal_mutation
    before_destroy :prevent_destroy

    scope :active, -> { where(status: ACTIVE_STATUSES) }
    scope :review_queue, -> { where(status: REVIEW_QUEUE_STATUSES) }
    scope :expired_drafts, ->(at = Time.current) { where(status: "draft", expires_at: ..at) }

    def draft_expired?(at = Time.current)
      draft? && expires_at.present? && expires_at <= at
    end

    private

    def role_matches_report
      return unless report && appellant

      expected = if appellant_role_reporter?
        report.reporter_id
      elsif appellant_role_affected_subject?
        report.affected_user_id
      end
      errors.add(:appellant_id, :invalid) unless expected == appellant_id
    end

    def state_shape
      case status
      when "draft"
        errors.add(:expires_at, :blank) if expires_at.blank?
        errors.add(:reason, :invalid) if reason.present?
      when "submitted"
        errors.add(:submitted_at, :blank) if submitted_at.blank?
        errors.add(:expires_at, :invalid) if expires_at.present?
      when "under_review"
        errors.add(:reviewer_id, :blank) if reviewer_id.blank?
        errors.add(:review_started_at, :blank) if review_started_at.blank?
      when "upheld", "overturned"
        errors.add(:reviewer_id, :blank) if reviewer_id.blank?
        errors.add(:decided_at, :blank) if decided_at.blank?
        errors.add(:public_outcome_code, :invalid) unless public_outcome_code == status
      when "cancelled"
        errors.add(:cancelled_at, :blank) if cancelled_at.blank?
        errors.add(:public_outcome_code, :invalid) unless public_outcome_code == "cancelled"
      end
    end

    def transition_is_valid
      return unless will_save_change_to_status?

      from, to = status_change_to_be_saved
      allowed = {
        "draft" => %w[submitted cancelled],
        "submitted" => %w[under_review cancelled],
        "under_review" => %w[upheld overturned]
      }
      errors.add(:status, :invalid) unless allowed.fetch(from, []).include?(to)
    end

    def mutation_identity_is_write_once
      from, to = if will_save_change_to_status?
        status_change_to_be_saved
      else
        [ status_in_database, status ]
      end
      contracts = {
        submit: [ "draft", [ "submitted" ] ],
        cancel: [ %w[draft submitted], [ "cancelled" ] ],
        decision: [ "under_review", %w[upheld overturned] ]
      }
      contracts.each do |prefix, (allowed_from, allowed_to)|
        digest_change = public_send("#{prefix}_idempotency_key_digest_change_to_be_saved")
        fingerprint_change = public_send("#{prefix}_request_fingerprint_change_to_be_saved")
        next unless digest_change || fingerprint_change

        first_write = Array(allowed_from).include?(from) && allowed_to.include?(to) &&
          digest_change&.first.nil? && digest_change&.last.present? &&
          fingerprint_change&.first.nil? && fingerprint_change&.last.present?
        errors.add(:base, :immutable) unless first_write
      end
    end

    def prevent_terminal_mutation
      return unless TERMINAL_STATUSES.include?(status_in_database)
      return if changes_to_save.empty?

      errors.add(:base, :immutable)
      throw(:abort)
    end

    def prevent_destroy
      errors.add(:base, :immutable)
      throw(:abort)
    end
  end
end
