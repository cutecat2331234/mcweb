# frozen_string_literal: true

module Commerce
  module Disputes
    class EvidenceDownloadToken
      PURPOSE = "commerce_dispute_evidence_download"
      EXPIRES_IN = 5.minutes

      class << self
        def issue(evidence:, actor:)
          return ServiceResult.failure(error: "dispute_evidence_unavailable") if evidence.purged?

          token = verifier.generate(
            {
              "evidence_id" => evidence.id,
              "public_id" => evidence.public_id,
              "sha256" => evidence.sha256,
              "actor_id" => actor.id,
              "nonce" => SecureRandom.hex(16)
            },
            purpose: PURPOSE,
            expires_in: EXPIRES_IN
          )
          ServiceResult.success(token: token, expires_in: EXPIRES_IN.to_i)
        end

        def valid?(token, evidence:, actor:)
          payload = verifier.verified(token.to_s, purpose: PURPOSE)
          return false unless payload.is_a?(Hash)
          return false unless payload["nonce"].to_s.match?(/\A[0-9a-f]{32}\z/)

          secure_match?(payload["evidence_id"], evidence.id) &&
            secure_match?(payload["public_id"], evidence.public_id) &&
            secure_match?(payload["sha256"], evidence.sha256) &&
            secure_match?(payload["actor_id"], actor.id) &&
            !evidence.purged?
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          false
        end

        private

        def verifier
          Rails.application.message_verifier(PURPOSE)
        end

        def secure_match?(left, right)
          left = left.to_s
          right = right.to_s
          left.bytesize == right.bytesize &&
            ActiveSupport::SecurityUtils.secure_compare(left, right)
        end
      end
    end
  end
end
