# frozen_string_literal: true

require "digest"

module Commerce
  class StoreCreditAdjustmentAuthorization
    PURPOSE = "store_credit_adjustment"
    ACTION = "store.credit.adjust"
    EXPIRES_IN = 5.minutes
    REQUEST_ID_FORMAT = Commerce::StoreCreditTransaction::REQUEST_ID_FORMAT
    NONCE_FORMAT = /\A[0-9a-f]{32}\z/
    MAX_NOTE_LENGTH = 1_000
    MAX_ABSOLUTE_AMOUNT_CENTS = 100_000_000
    MAX_BALANCE_CENTS = (2**31) - 1

    class << self
      def issue(actor:, user:, amount_cents:, request_id:, note:)
        amount = normalize_amount(amount_cents)
        normalized_request_id = normalize_request_id(request_id)
        normalized_note = normalize_note(note)

        return ServiceResult.failure(error: "store_credit_unauthorized") unless authorized?(actor, user)
        return ServiceResult.failure(error: "store_credit_amount_invalid") if amount.nil?
        return ServiceResult.failure(error: "store_credit_adjustment_zero") if amount.zero?
        if amount.abs > MAX_ABSOLUTE_AMOUNT_CENTS
          return ServiceResult.failure(error: "store_credit_amount_out_of_range")
        end
        return ServiceResult.failure(error: "store_credit_request_id_invalid") unless normalized_request_id
        return ServiceResult.failure(error: "store_credit_note_required") if normalized_note.blank?
        if normalized_note.length > MAX_NOTE_LENGTH
          return ServiceResult.failure(error: "store_credit_note_too_long")
        end

        user.reload
        balance_before = user.store_credit_cents.to_i
        balance_after = balance_before + amount
        return ServiceResult.failure(error: "store_credit_negative_balance") if balance_after.negative?
        if balance_after > MAX_BALANCE_CENTS
          return ServiceResult.failure(error: "store_credit_balance_out_of_range")
        end

        reserved = balance_before - user.available_store_credit_cents
        if balance_after < reserved
          return ServiceResult.failure(error: "store_credit_below_reserved")
        end

        confirmation = confirmation_for(
          user: user,
          amount_cents: amount,
          request_id: normalized_request_id
        )
        payload = token_payload(
          actor: actor,
          user: user,
          current_balance_cents: balance_before,
          amount_cents: amount,
          request_id: normalized_request_id,
          note: normalized_note
        ).merge(
          "nonce" => SecureRandom.hex(16)
        )

        token = verifier.generate(
          payload,
          purpose: PURPOSE,
          expires_in: EXPIRES_IN
        )

        ServiceResult.success(
          token: token,
          confirmation: confirmation,
          request_id: normalized_request_id,
          amount_cents: amount,
          balance_before_cents: balance_before,
          balance_after_cents: balance_after,
          expires_in: EXPIRES_IN.to_i
        )
      end

      def valid?(token, actor:, user:, current_balance_cents:, amount_cents:, request_id:, note:)
        amount = normalize_amount(amount_cents)
        normalized_request_id = normalize_request_id(request_id)
        normalized_note = normalize_note(note)
        return false unless amount && normalized_request_id && normalized_note.present?

        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)
        return false unless payload["nonce"].to_s.match?(NONCE_FORMAT)

        expected = token_payload(
          actor: actor,
          user: user,
          current_balance_cents: current_balance_cents,
          amount_cents: amount,
          request_id: normalized_request_id,
          note: normalized_note
        )
        expected.all? do |key, value|
          secure_match?(payload[key], value)
        end
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        false
      end

      def confirmation_for(user:, amount_cents:, request_id:)
        amount = normalize_amount(amount_cents)
        normalized_request_id = normalize_request_id(request_id)
        return "" unless amount && normalized_request_id

        identifier = user.respond_to?(:public_id) ? user.public_id.presence : nil
        "ADJUST #{identifier || user.id} #{format('%+d', amount)} #{normalized_request_id.last(8).upcase}"
      end

      def request_fingerprint(actor:, user:, amount_cents:, request_id:, note:)
        amount = normalize_amount(amount_cents)
        normalized_request_id = normalize_request_id(request_id)
        normalized_note = normalize_note(note)
        return unless amount && normalized_request_id && normalized_note.present?

        Digest::SHA256.hexdigest(
          JSON.generate(
            {
              action: ACTION,
              actor_id: actor&.id.to_s,
              user_id: user&.id.to_s,
              amount_cents: amount,
              request_id: normalized_request_id,
              note: normalized_note
            }
          )
        )
      end

      def authorization_digest(token)
        Digest::SHA256.hexdigest(token.to_s)
      end

      def normalize_request_id(value)
        normalized = value.to_s.strip.downcase
        return if normalized.blank? || !REQUEST_ID_FORMAT.match?(normalized)

        normalized
      end

      def normalize_note(value)
        value.to_s.strip
      end

      def normalize_amount(value)
        return value if value.is_a?(Integer)
        return if value.nil?

        Integer(value.to_s, 10, exception: false)
      end

      private

      def authorized?(actor, user)
        actor.present? &&
          user.present? &&
          actor.id != user.id &&
          actor.permission?(ACTION)
      end

      def token_payload(actor:, user:, current_balance_cents:, amount_cents:, request_id:, note:)
        {
          "action" => ACTION,
          "actor_id" => actor&.id.to_s,
          "user_id" => user&.id.to_s,
          "user_public_id" => (user.respond_to?(:public_id) ? user.public_id.to_s : ""),
          "current_balance_cents" => current_balance_cents.to_i.to_s,
          "amount_cents" => amount_cents.to_i.to_s,
          "request_id" => request_id.to_s,
          "note_digest" => Digest::SHA256.hexdigest(note.to_s)
        }
      end

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
