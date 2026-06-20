# frozen_string_literal: true

module Minecraft
  class GeneratePairingToken < ApplicationService
    TTL = 15.minutes

    def initialize(node:)
      @node = node
    end

    def call
      token = SecureRandom.urlsafe_base64(32)
      metadata = @node.metadata.merge(
        "pairing_token" => token,
        "pairing_token_expires_at" => TTL.from_now.iso8601
      )
      @node.update!(metadata: metadata)

      ServiceResult.success(
        token: token,
        expires_at: metadata["pairing_token_expires_at"]
      )
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
