# frozen_string_literal: true

require "digest"

module Community
  module ModerationWorkbench
    class ActionAuthorization
      PURPOSE = "forum_moderation_workbench_action"
      EXPIRES_IN = 5.minutes
      MAX_CASES = 100
      MAX_REASON_LENGTH = 1_000
      NONCE_FORMAT = /\A[0-9a-f]{32}\z/

      class << self
        def issue(actor:, action:, moderation_cases:, attributes:, request_id:, reason:)
          normalized = normalized_input(
            actor: actor,
            action: action,
            moderation_cases: moderation_cases,
            attributes: attributes,
            request_id: request_id,
            reason: reason
          )
          error = input_error(normalized)
          return ServiceResult.failure(error: error) if error

          plan = ActionPlan.new(
            actor: actor,
            action: normalized[:action],
            moderation_cases: normalized[:moderation_cases],
            attributes: normalized[:attributes]
          )
          return ServiceResult.failure(error: "moderation_action_invalid") unless plan.valid_action?
          return ServiceResult.failure(error: "moderation_no_eligible_cases") unless plan.any_eligible?
          if normalized[:action] == "release_attachment" && normalized[:reason].length <
              Community::ReleaseQuarantinedUpload::MIN_REASON_LENGTH
            return ServiceResult.failure(error: "moderation_release_reason_too_short")
          end

          confirmation = confirmation_for(
            action: normalized[:action],
            case_ids: normalized[:case_ids],
            request_id: normalized[:request_id]
          )
          payload = token_payload(normalized, state: plan.state).merge(
            "nonce" => SecureRandom.hex(16)
          )
          token = verifier.generate(payload, purpose: PURPOSE, expires_in: EXPIRES_IN)

          ServiceResult.success(
            authorization_token: token,
            typed_confirmation: confirmation,
            request_id: normalized[:request_id],
            action: normalized[:action],
            expires_at: EXPIRES_IN.from_now.iso8601,
            preview: plan.preview
          )
        end

        def valid?(token, actor:, action:, moderation_cases:, state:, attributes:,
                   request_id:, reason:)
          normalized = normalized_input(
            actor: actor,
            action: action,
            moderation_cases: moderation_cases,
            attributes: attributes,
            request_id: request_id,
            reason: reason
          )
          return false if input_error(normalized)

          payload = verifier.verified(token.to_s, purpose: PURPOSE)
          return false unless payload.is_a?(Hash)
          return false unless payload["nonce"].to_s.match?(NONCE_FORMAT)

          token_payload(normalized, state: state).all? do |key, value|
            secure_match?(payload[key], value)
          end
        rescue ActiveSupport::MessageVerifier::InvalidSignature
          false
        end

        def confirmation_valid?(confirmation, action:, case_ids:, request_id:)
          secure_match?(
            confirmation.to_s.strip,
            confirmation_for(action: action, case_ids: case_ids, request_id: request_id)
          )
        end

        def confirmation_for(action:, case_ids:, request_id:)
          normalized_action = action.to_s.strip.downcase
          normalized_request_id = normalize_request_id(request_id)
          ids = normalize_case_ids(case_ids)
          return "" unless ActionPlan::ACTIONS.include?(normalized_action)
          return "" unless normalized_request_id && ids.any?

          digest = Digest::SHA256.hexdigest(JSON.generate(ids)).first(8).upcase
          "CONFIRM #{normalized_action.upcase} #{digest} #{normalized_request_id.last(8).upcase}"
        end

        def request_fingerprint(actor:, action:, case_ids:, attributes:, request_id:, reason:)
          normalized_request_id = normalize_request_id(request_id)
          ids = normalize_case_ids(case_ids)
          return unless actor && normalized_request_id && ids.any?

          Digest::SHA256.hexdigest(
            canonical_json(
              actor_id: actor.id,
              action: action.to_s.strip.downcase,
              case_ids: ids,
              attributes: canonicalize(attributes),
              request_id: normalized_request_id,
              reason: normalize_reason(reason)
            )
          )
        end

        def authorization_digest(token)
          Digest::SHA256.hexdigest(token.to_s)
        end

        def normalize_request_id(value)
          normalized = value.to_s.strip.downcase
          normalized if Community::ModerationOperation::REQUEST_ID_FORMAT.match?(normalized)
        end

        def normalize_case_ids(values)
          Array(values).filter_map { |value| Integer(value, exception: false) }
            .select(&:positive?)
            .uniq
            .sort
        end

        def normalize_reason(value)
          value.to_s.strip
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

        def normalized_input(actor:, action:, moderation_cases:, attributes:, request_id:, reason:)
          cases = Array(moderation_cases).sort_by(&:id)
          {
            actor: actor,
            action: action.to_s.strip.downcase,
            moderation_cases: cases,
            case_ids: cases.map(&:id),
            attributes: canonicalize(attributes),
            request_id: normalize_request_id(request_id),
            reason: normalize_reason(reason)
          }
        end

        def input_error(normalized)
          return "moderation_action_invalid" unless ActionPlan::ACTIONS.include?(normalized[:action])
          return "moderation_request_id_invalid" unless normalized[:request_id]
          return "moderation_reason_required" if normalized[:reason].blank?
          return "moderation_reason_too_long" if normalized[:reason].length > MAX_REASON_LENGTH
          return "moderation_cases_required" if normalized[:case_ids].empty?
          return "moderation_too_many_cases" if normalized[:case_ids].size > MAX_CASES
          return "moderation_actor_required" unless normalized[:actor]

          nil
        end

        def token_payload(normalized, state:)
          {
            "action" => normalized[:action],
            "actor_id" => normalized[:actor].id.to_s,
            "request_id" => normalized[:request_id],
            "reason_digest" => Digest::SHA256.hexdigest(normalized[:reason]),
            "cases_digest" => Digest::SHA256.hexdigest(canonical_json(normalized[:case_ids])),
            "state_digest" => Digest::SHA256.hexdigest(canonical_json(state)),
            "attributes_digest" => Digest::SHA256.hexdigest(
              canonical_json(normalized[:attributes])
            )
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
end
