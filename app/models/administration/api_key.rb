# frozen_string_literal: true

require "digest"

module Administration
  # API key for the public REST API (see Api::V1). The plaintext token is shown
  # exactly once at creation time; only a SHA-256 digest is stored. A key may
  # optionally act as a specific user for permission-scoped access; when no user
  # is associated it is treated as an anonymous/guest reader.
  class ApiKey < ApplicationRecord
    self.table_name = "api_keys"

    TOKEN_PREFIX = "mcw_"
    STAFF_READ_SCOPE = "staff.moderation.read"
    STAFF_MUTATION_SCOPES = %w[
      staff.moderation.claim
      staff.moderation.assign
      staff.moderation.note
      staff.moderation.execute
    ].freeze
    VALID_SCOPES = (
      %w[read write] + [ STAFF_READ_SCOPE ] + STAFF_MUTATION_SCOPES
    ).freeze

    belongs_to :user, class_name: "User", optional: true
    belongs_to :created_by, class_name: "User", optional: true

    validates :name, presence: true
    validates :public_id, presence: true, uniqueness: true
    validates :token_digest, presence: true, uniqueness: true

    scope :active, -> { where(revoked_at: nil) }

    # Generate a new key. Returns [record, plaintext_token]. The plaintext is not
    # persisted and cannot be recovered later.
    def self.generate!(name:, scopes: %w[read], user: nil, created_by: nil)
      requested_scopes = Array(scopes).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      unless valid_scope_set?(requested_scopes)
        raise ArgumentError, "scopes must contain at least one of: #{VALID_SCOPES.join(', ')}"
      end

      secret = SecureRandom.urlsafe_base64(32)
      plaintext = "#{TOKEN_PREFIX}#{secret}"
      record = create!(
        public_id: "apik_#{SecureRandom.alphanumeric(16)}",
        name: name,
        token_digest: digest(plaintext),
        token_prefix: plaintext[0, 12],
        scopes: requested_scopes.join(","),
        user: user,
        created_by: created_by
      )
      [ record, plaintext ]
    end

    def self.valid_scope_set?(scopes)
      requested = Array(scopes).map(&:to_s).map(&:strip).reject(&:blank?).uniq
      return false if requested.empty? || (requested - VALID_SCOPES).any?
      return false if (requested & STAFF_MUTATION_SCOPES).any? &&
        !requested.include?(STAFF_READ_SCOPE)

      true
    end

    # Look up an active key by plaintext token using a constant-time digest match.
    def self.authenticate(token)
      token = token.to_s
      return nil unless token.start_with?(TOKEN_PREFIX)

      key = active.find_by(token_digest: digest(token))
      return nil unless key
      return nil if key.user && (key.user.deleted? || key.user.banned?)

      key.touch(:last_used_at)
      key
    end

    def self.digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    def scope_list
      scopes.to_s.split(",").map(&:strip).reject(&:blank?)
    end

    def allows?(scope)
      scope_list.include?(scope.to_s)
    end

    def revoked?
      revoked_at.present?
    end

    def revoke!
      update!(revoked_at: Time.current)
    end
  end
end
