# frozen_string_literal: true

require "digest"

module Commerce
  class HighRiskActionAuthorization
    PURPOSE = "commerce_high_risk_action"
    EXPIRES_IN = 5.minutes
    MAX_REASON_LENGTH = 1_000
    NONCE_FORMAT = /\A[0-9a-f]{32}\z/

    ACTION_PERMISSIONS = {
      "membership.grant" => "store.entitlements.grant",
      "membership.revoke" => "store.entitlements.revoke",
      "entitlement.grant" => "store.entitlements.grant",
      "entitlement.revoke" => "store.entitlements.revoke",
      "order.mark_paid" => "store.orders.mark_paid",
      "order.mark_fulfilled" => "store.orders.mark_fulfilled",
      "order.cancel" => "store.orders.cancel",
      "inventory.adjust" => "store.inventory.adjust",
      "fulfillment.retry" => "store.fulfillments.retry",
      "fulfillment.cancel" => "store.fulfillments.cancel",
      "dispute.accept_loss" => "store.disputes.accept_loss",
      "dispute.rights.freeze" => "store.disputes.rights_manage",
      "dispute.rights.revoke" => "store.disputes.rights_manage",
      "dispute.rights.restore" => "store.disputes.rights_manage"
    }.freeze

    class << self
      def issue(actor:, action:, targets:, state:, attributes:, request_id:, reason:)
        normalized = normalized_input(
          actor: actor,
          action: action,
          targets: targets,
          state: state,
          attributes: attributes,
          request_id: request_id,
          reason: reason
        )
        error = input_error(normalized)
        return ServiceResult.failure(error: error) if error
        return ServiceResult.failure(error: "high_risk_unauthorized") unless authorized?(actor, normalized[:action])

        confirmation = confirmation_for(
          action: normalized[:action],
          targets: normalized[:targets],
          request_id: normalized[:request_id]
        )
        payload = token_payload(normalized).merge("nonce" => SecureRandom.hex(16))
        token = verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)

        ServiceResult.success(
          authorization_token: token,
          confirmation: confirmation,
          request_id: normalized[:request_id],
          action: normalized[:action],
          expires_in: EXPIRES_IN.to_i
        )
      end

      def valid?(token, actor:, action:, targets:, state:, attributes:, request_id:, reason:)
        normalized = normalized_input(
          actor: actor,
          action: action,
          targets: targets,
          state: state,
          attributes: attributes,
          request_id: request_id,
          reason: reason
        )
        return false if input_error(normalized)
        return false unless authorized?(actor, normalized[:action])

        payload = verifier.verified(token.to_s, purpose: PURPOSE)
        return false unless payload.is_a?(Hash)
        return false unless payload["nonce"].to_s.match?(NONCE_FORMAT)

        token_payload(normalized).all? do |key, value|
          secure_match?(payload[key], value)
        end
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        false
      end

      def confirmation_valid?(confirmation, action:, targets:, request_id:)
        expected = confirmation_for(action: action, targets: targets, request_id: request_id)
        secure_match?(confirmation.to_s.strip, expected)
      end

      def confirmation_for(action:, targets:, request_id:)
        normalized_action = normalize_action(action)
        normalized_request_id = normalize_request_id(request_id)
        normalized_targets = canonicalize(targets)
        return "" unless ACTION_PERMISSIONS.key?(normalized_action) && normalized_request_id

        target_digest = Digest::SHA256.hexdigest(canonical_json(normalized_targets)).first(8).upcase
        verb = normalized_action.tr(".", "_").upcase
        "CONFIRM #{verb} #{target_digest} #{normalized_request_id.last(8).upcase}"
      end

      def request_fingerprint(actor:, action:, targets:, attributes:, request_id:, reason:)
        normalized = normalized_input(
          actor: actor,
          action: action,
          targets: targets,
          state: {},
          attributes: attributes,
          request_id: request_id,
          reason: reason
        )
        return if input_error(normalized)

        Digest::SHA256.hexdigest(
          canonical_json(
            action: normalized[:action],
            actor_id: actor&.id.to_s,
            targets: normalized[:targets],
            attributes: normalized[:attributes],
            request_id: normalized[:request_id],
            reason: normalized[:reason]
          )
        )
      end

      def authorization_digest(token)
        Digest::SHA256.hexdigest(token.to_s)
      end

      def normalize_request_id(value)
        normalized = value.to_s.strip.downcase
        return unless Commerce::HighRiskOperation::REQUEST_ID_FORMAT.match?(normalized)

        normalized
      end

      def normalize_reason(value)
        value.to_s.strip
      end

      def permission_for(action)
        ACTION_PERMISSIONS[normalize_action(action)]
      end

      def canonicalize(value)
        case value
        when ActionController::Parameters
          canonicalize(value.to_unsafe_h)
        when Hash
          value.each_with_object({}) do |(key, child), result|
            result[key.to_s] = canonicalize(child)
          end.sort.to_h
        when Array
          value.map { |child| canonicalize(child) }
        when Time, ActiveSupport::TimeWithZone, DateTime
          value.iso8601(6)
        when Date
          value.iso8601
        when BigDecimal
          value.to_s("F")
        else
          value
        end
      end

      private

      def normalized_input(actor:, action:, targets:, state:, attributes:, request_id:, reason:)
        {
          actor: actor,
          action: normalize_action(action),
          targets: canonicalize(targets),
          state: canonicalize(state),
          attributes: canonicalize(attributes),
          request_id: normalize_request_id(request_id),
          reason: normalize_reason(reason)
        }
      end

      def input_error(normalized)
        return "high_risk_action_invalid" unless ACTION_PERMISSIONS.key?(normalized[:action])
        return "high_risk_request_id_invalid" unless normalized[:request_id]
        return "high_risk_reason_required" if normalized[:reason].blank?
        return "high_risk_reason_too_long" if normalized[:reason].length > MAX_REASON_LENGTH
        return "high_risk_targets_required" if Array(normalized[:targets]).empty?

        nil
      end

      def normalize_action(value)
        value.to_s.strip.downcase
      end

      def authorized?(actor, action)
        permission = permission_for(action)
        actor.present? && permission.present? && actor.permission?(permission)
      end

      def token_payload(normalized)
        {
          "action" => normalized[:action],
          "actor_id" => normalized[:actor]&.id.to_s,
          "request_id" => normalized[:request_id].to_s,
          "reason_digest" => Digest::SHA256.hexdigest(normalized[:reason]),
          "targets_digest" => Digest::SHA256.hexdigest(canonical_json(normalized[:targets])),
          "state_digest" => Digest::SHA256.hexdigest(canonical_json(normalized[:state])),
          "attributes_digest" => Digest::SHA256.hexdigest(canonical_json(normalized[:attributes]))
        }
      end

      def canonical_json(value)
        JSON.generate(canonicalize(value))
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
