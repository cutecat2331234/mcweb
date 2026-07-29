# frozen_string_literal: true

module Community
  class ModerationOperation < ApplicationRecord
    self.table_name = "forum_moderation_operations"

    REQUEST_ID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
    SHA256_FORMAT = /\A[0-9a-f]{64}\z/
    ACTION_FORMAT = /\A[a-z][a-z0-9_]{2,63}\z/

    belongs_to :actor, class_name: "User"

    before_validation :normalize_request_id
    before_update { throw(:abort) }
    before_destroy { throw(:abort) }

    validates :action, format: { with: ACTION_FORMAT }
    validates :request_id, format: { with: REQUEST_ID_FORMAT }, uniqueness: true
    validates :request_fingerprint, :authorization_digest,
      format: { with: SHA256_FORMAT }
    validates :authorization_digest, uniqueness: true
    validates :reason, presence: true, length: { maximum: 1_000 }

    private

    def normalize_request_id
      self.request_id = request_id.to_s.strip.downcase
    end
  end
end
