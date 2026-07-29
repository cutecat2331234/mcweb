# frozen_string_literal: true

require "digest"
require "json"
require_relative "normalizer"
require_relative "outbound_delivery_snapshot"
require_relative "result"

module Mcweb
  module PluginApi
    module V1
      module OutboundSupport
        MAX_PAYLOAD_BYTES = 262_144
        MAX_TEXT_LENGTH = 100_000
        MAX_TYPE_LENGTH = 191
        MAX_RECIPIENT_LENGTH = 320
        TYPE_PATTERN = /\A[a-z][a-z0-9_]*(?:[.-][a-z0-9_]+)*\z/

        private

        def enqueue_delivery(
          kind:,
          idempotency_key:,
          payload:,
          user: nil,
          destination: nil,
          secret: nil,
          max_attempts: 5
        )
          normalized_key = idempotency_key.to_s
          unless normalized_key.match?(PluginOutboundDelivery::IDEMPOTENCY_PATTERN) &&
              normalized_key.length <= 191
            return Result.failure(
              code: "invalid_idempotency_key",
              error: "idempotency_key has an invalid format"
            )
          end

          normalized_payload = normalize_payload(payload)
          return normalized_payload if normalized_payload.is_a?(Result)

          attempts = Integer(max_attempts, exception: false)
          unless attempts&.between?(1, 10)
            return Result.failure(
              code: "invalid_argument",
              error: "max_attempts must be between 1 and 10"
            )
          end

          request_digest = delivery_request_digest(
            payload: normalized_payload,
            user:,
            destination:,
            secret:,
            max_attempts: attempts
          )
          delivery = nil
          idempotent = false

          PluginOutboundDelivery.transaction do
            delivery = PluginOutboundDelivery
              .owned_by(@plugin_id)
              .lock
              .find_by(kind:, idempotency_key: normalized_key)

            if delivery
              unless secure_digest_match?(delivery.payload_digest, request_digest)
                return Result.failure(
                  code: "idempotency_conflict",
                  error: "idempotency_key was already used with different input"
                )
              end
              idempotent = true
            else
              delivery = PluginOutboundDelivery.create!(
                owner_plugin_id: @plugin_id,
                kind:,
                idempotency_key: normalized_key,
                user:,
                destination: destination&.to_s,
                payload: normalized_payload,
                secret: secret&.to_s,
                payload_digest: request_digest,
                max_attempts: attempts
              )
              public_id = delivery.public_id
              ActiveRecord.after_all_transactions_commit do
                PluginOutboundDeliveryJob.perform_later(public_id)
              end
            end
          end

          Result.success(OutboundDeliverySnapshot.call(delivery, idempotent:))
        rescue ActiveRecord::RecordNotUnique
          retry_delivery_after_unique_race(
            kind:,
            idempotency_key: normalized_key,
            request_digest:
          )
        rescue ActiveRecord::RecordInvalid => e
          Result.failure(
            code: "invalid_argument",
            error: "outbound delivery is invalid",
            errors: e.record.errors.to_hash
          )
        rescue StandardError
          Result.failure(
            code: "host_error",
            error: "outbound delivery operation failed"
          )
        end

        def find_delivery(public_id:, kind:)
          public_id = public_id.to_s
          delivery = PluginOutboundDelivery
            .owned_by(@plugin_id)
            .find_by(public_id:, kind:)
          return Result.failure(code: "not_found", error: "delivery not found") unless delivery

          Result.success(OutboundDeliverySnapshot.call(delivery))
        rescue StandardError
          Result.failure(code: "host_error", error: "outbound delivery operation failed")
        end

        def normalize_payload(payload)
          unless payload.is_a?(Hash)
            return Result.failure(code: "invalid_argument", error: "payload must be a mapping")
          end

          json = JSON.generate(payload)
          if json.bytesize > MAX_PAYLOAD_BYTES
            return Result.failure(
              code: "payload_too_large",
              error: "payload exceeds #{MAX_PAYLOAD_BYTES} bytes"
            )
          end

          JSON.parse(json)
        rescue JSON::GeneratorError, EncodingError
          Result.failure(code: "invalid_argument", error: "payload must be JSON compatible")
        end

        def delivery_request_digest(payload:, user:, destination:, secret:, max_attempts:)
          Digest::SHA256.hexdigest(
            JSON.generate(
              {
                payload:,
                user_id: user&.id,
                destination: destination&.to_s,
                secret: secret&.to_s,
                max_attempts:
              }
            )
          )
        end

        def retry_delivery_after_unique_race(kind:, idempotency_key:, request_digest:)
          delivery = PluginOutboundDelivery
            .owned_by(@plugin_id)
            .find_by(kind:, idempotency_key:)
          unless delivery && secure_digest_match?(delivery.payload_digest, request_digest)
            return Result.failure(
              code: "idempotency_conflict",
              error: "idempotency_key was already used with different input"
            )
          end

          Result.success(OutboundDeliverySnapshot.call(delivery, idempotent: true))
        end

        def secure_digest_match?(left, right)
          left = left.to_s
          right = right.to_s
          left.bytesize == right.bytesize &&
            ActiveSupport::SecurityUtils.secure_compare(left, right)
        end

        def resolve_recipient(user)
          unless user.is_a?(::User) && user.persisted?
            return [ nil, Result.failure(
              code: "invalid_user",
              error: "a persisted user is required"
            ) ]
          end

          [ user, nil ]
        end

        def normalize_type(value, field: "type")
          type = value.to_s
          unless type.length.between?(1, MAX_TYPE_LENGTH) && type.match?(TYPE_PATTERN)
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "#{field} has an invalid format"
            ) ]
          end

          [ type, nil ]
        end

        def normalize_text(value, field:, required: false, maximum: MAX_TEXT_LENGTH)
          text = value.to_s
          if (required && text.blank?) || text.length > maximum
            return [ nil, Result.failure(
              code: "invalid_argument",
              error: "#{field} is invalid"
            ) ]
          end

          [ text, nil ]
        end

        def plugin_notification_type(value)
          type, failure = normalize_type(value, field: "notification_type")
          return [ nil, failure ] if failure

          namespace = @plugin_id.tr("/_-", ".")
          [ "plugin.#{namespace}.#{type}", nil ]
        end
      end
    end
  end
end
