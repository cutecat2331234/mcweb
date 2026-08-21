# frozen_string_literal: true

class NavigationReceipt
  PURPOSE = "navigation_receipt"
  EXPIRES_IN = 10.minutes
  CONSUMED_FOR = 15.minutes

  class << self
    attr_writer :cache_store

    def issue(kind:, resource_id:, user_id:, attributes: {})
      verifier.generate(
        {
          "kind" => kind.to_s,
          "resource_id" => resource_id.to_s,
          "user_id" => user_id&.to_s,
          "nonce" => SecureRandom.hex(16),
          "attributes" => attributes.to_h.stringify_keys
        },
        purpose: PURPOSE,
        expires_in: EXPIRES_IN
      )
    end

    def consume(token:, kind:, resource_id:, user_id:)
      payload = verified_payload(token)
      return invalid_receipt unless valid_payload?(
        payload,
        kind: kind,
        resource_id: resource_id,
        user_id: user_id
      )

      fresh = cache_store.write(
        consumed_key(payload.fetch("nonce")),
        true,
        expires_in: CONSUMED_FOR,
        unless_exist: true
      )

      attributes = payload.fetch("attributes", {}).to_h.symbolize_keys
      if fresh && block_given?
        begin
          yield attributes
        rescue StandardError
          cache_store.delete(consumed_key(payload.fetch("nonce")))
          raise
        end
      end

      ServiceResult.success(
        fresh: fresh,
        attributes: attributes
      )
    end

    def cache_store
      @cache_store || Rails.cache
    end

    private

    def verifier
      Rails.application.message_verifier(PURPOSE)
    end

    def verified_payload(token)
      verifier.verified(token.to_s, purpose: PURPOSE)
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      nil
    end

    def valid_payload?(payload, kind:, resource_id:, user_id:)
      payload.is_a?(Hash) &&
        payload["kind"] == kind.to_s &&
        payload["resource_id"] == resource_id.to_s &&
        payload["user_id"] == user_id&.to_s &&
        payload["nonce"].present? &&
        payload.fetch("attributes", {}).is_a?(Hash)
    end

    def consumed_key(nonce)
      "navigation_receipt:v1:#{Digest::SHA256.hexdigest(nonce.to_s)}"
    end

    def invalid_receipt
      ServiceResult.failure(code: "invalid_navigation_receipt")
    end
  end
end
