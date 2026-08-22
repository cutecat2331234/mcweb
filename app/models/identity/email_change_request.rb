# frozen_string_literal: true

module Identity
  class EmailChangeRequest < ApplicationRecord
    self.table_name = "identity_email_change_requests"

    CONFIRMATION_TTL = 24.hours
    REVERSAL_TTL = 24.hours

    belongs_to :user
    belongs_to :initiating_session, class_name: "Session", optional: true

    has_encrypted :confirmation_token
    has_encrypted :revocation_token

    enum :status, {
      pending: "pending",
      confirmed: "confirmed",
      revoked: "revoked",
      superseded: "superseded",
      expired: "expired"
    }, validate: true

    validates :original_email, :requested_email,
              presence: true,
              format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :confirmation_token_digest, :revocation_token_digest,
              presence: true,
              uniqueness: true
    validates :confirmation_token, :revocation_token, presence: true, on: :create
    validates :requested_at, :expires_at, presence: true

    scope :active_pending, ->(at = Time.current) { pending.where("expires_at > ?", at) }
    scope :reversible, ->(at = Time.current) { confirmed.where("revert_expires_at > ?", at) }
    scope :recent_first, -> { order(requested_at: :desc, id: :desc) }

    def self.email_reserved?(email, except_user_id: nil, at: Time.current)
      normalized = email.to_s.strip.downcase
      return false if normalized.blank?

      scope = all
      scope = scope.where.not(user_id: except_user_id) if except_user_id
      scope.where(
        <<~SQL.squish,
          (
            status = 'pending' AND expires_at > :at AND LOWER(requested_email) = :email
          ) OR (
            status = 'confirmed' AND revert_expires_at > :at AND LOWER(original_email) = :email
          )
        SQL
        at:,
        email: normalized
      ).exists?
    end

    def confirmation_expired?(at = Time.current)
      expires_at <= at
    end

    def reversal_expired?(at = Time.current)
      revert_expires_at.blank? || revert_expires_at <= at
    end
  end
end
