# frozen_string_literal: true

module Payments
  class StripeReconciliationAdapter
    class EnvironmentMismatch < StandardError; end

    PAGE_SIZE = 100
    PAYMENT_REFERENCE_PATTERN = /\Api_[A-Za-z0-9_]+\z/
    REFUND_REFERENCE_PATTERN = /\Are_[A-Za-z0-9_]+\z/
    STATUS_PATTERN = /\A[a-z_]{1,40}\z/
    CURRENCY_PATTERN = /\A[A-Z]{3}\z/

    def initialize(
      secret_key: nil,
      expected_mode:,
      client: nil,
      client_builder: Payments::StripeReconciliationClient.new
    )
      @expected_mode = expected_mode.to_s
      @client = client || client_builder.build(secret_key: secret_key)
    end

    def payment_page(window_start:, window_end:, cursor: nil)
      list_page(
        resource: @client.v1.payment_intents,
        subject_type: "payment",
        window_start: window_start,
        window_end: window_end,
        cursor: cursor
      )
    end

    def refund_page(window_start:, window_end:, cursor: nil)
      list_page(
        resource: @client.v1.refunds,
        subject_type: "refund",
        window_start: window_start,
        window_end: window_end,
        cursor: cursor
      )
    end

    private

    def list_page(resource:, subject_type:, window_start:, window_end:, cursor:)
      params = {
        created: {
          gte: window_start.to_i,
          lt: window_end.to_i
        },
        limit: PAGE_SIZE
      }
      params[:starting_after] = cursor if cursor.present?

      response = resource.list(params)
      data = stripe_value(response, :data)
      has_more = stripe_value(response, :has_more)
      return invalid_response unless data.is_a?(Array) && [ true, false ].include?(has_more)

      items = data.map do |object|
        subject_type == "payment" ? normalize_payment(object) : normalize_refund(object)
      end
      return invalid_response if items.any?(&:nil?)

      next_cursor = has_more ? items.last&.fetch(:reference, nil) : nil
      if has_more && (next_cursor.blank? || next_cursor == cursor)
        return invalid_response
      end

      ServiceResult.success(items: items, next_cursor: next_cursor)
    rescue Stripe::AuthenticationError
      failure("authentication_failed")
    rescue Stripe::PermissionError
      failure("permission_denied")
    rescue Stripe::RateLimitError
      failure("rate_limited")
    rescue Stripe::APIConnectionError
      failure("provider_unavailable")
    rescue Stripe::StripeError
      failure("provider_error")
    rescue EnvironmentMismatch
      failure("environment_mismatch")
    end

    def normalize_payment(object)
      reference = stripe_value(object, :id).to_s
      status = stripe_value(object, :status).to_s
      currency = stripe_value(object, :currency).to_s.upcase
      livemode = stripe_value(object, :livemode)
      amount =
        if status == "succeeded"
          stripe_value(object, :amount_received)
        end
      amount = stripe_value(object, :amount) if amount.nil?
      metadata = safe_metadata(stripe_value(object, :metadata))

      return unless valid_common_item?(
        reference: reference,
        reference_pattern: PAYMENT_REFERENCE_PATTERN,
        status: status,
        currency: currency,
        livemode: livemode,
        amount: amount
      )

      {
        reference: reference,
        status: status,
        amount_cents: amount.to_i,
        currency: currency,
        local_payment_record_id: safe_local_id(metadata["payment_record_id"]),
        local_order_public_id: safe_public_id(metadata["order_public_id"]),
        metadata_valid: metadata_identifiers_valid?(
          metadata,
          numeric: %w[payment_record_id],
          public: %w[order_public_id]
        )
      }
    end

    def normalize_refund(object)
      reference = stripe_value(object, :id).to_s
      status = stripe_value(object, :status).to_s
      currency = stripe_value(object, :currency).to_s.upcase
      livemode = stripe_value(object, :livemode)
      amount = stripe_value(object, :amount)
      metadata = safe_metadata(stripe_value(object, :metadata))
      payment_reference = provider_reference(stripe_value(object, :payment_intent))

      return unless valid_common_item?(
        reference: reference,
        reference_pattern: REFUND_REFERENCE_PATTERN,
        status: status,
        currency: currency,
        livemode: livemode,
        amount: amount
      )
      return unless payment_reference.match?(PAYMENT_REFERENCE_PATTERN)

      {
        reference: reference,
        payment_reference: payment_reference,
        status: status,
        amount_cents: amount.to_i,
        currency: currency,
        local_refund_id: safe_local_id(metadata["mcweb_refund_id"]),
        local_payment_record_id: safe_local_id(metadata["payment_record_id"]),
        local_order_public_id: safe_public_id(metadata["order_public_id"]),
        metadata_valid: metadata_identifiers_valid?(
          metadata,
          numeric: %w[mcweb_refund_id payment_record_id],
          public: %w[order_public_id]
        )
      }
    end

    def valid_common_item?(reference:, reference_pattern:, status:, currency:, livemode:, amount:)
      return false unless reference.match?(reference_pattern)
      return false unless status.match?(STATUS_PATTERN)
      return false unless currency.match?(CURRENCY_PATTERN)
      return false unless amount.is_a?(Integer) && amount >= 0
      return false unless [ true, false ].include?(livemode)

      raise EnvironmentMismatch unless livemode == (@expected_mode == "live")

      true
    end

    def safe_metadata(value)
      hash =
        if value.respond_to?(:to_hash)
          value.to_hash
        elsif value.is_a?(Hash)
          value
        else
          {}
        end

      hash.stringify_keys
    end

    def provider_reference(value)
      value = value.id if value.respond_to?(:id)
      value.to_s
    end

    def safe_local_id(value)
      text = value.to_s
      return unless text.match?(/\A[1-9]\d{0,18}\z/)

      text.to_i
    end

    def safe_public_id(value)
      text = value.to_s
      return unless text.match?(/\A[A-Za-z0-9_-]{1,100}\z/)

      text
    end

    def metadata_identifiers_valid?(metadata, numeric:, public:)
      numeric.all? do |key|
        !metadata.key?(key) || metadata[key].blank? || safe_local_id(metadata[key]).present?
      end &&
        public.all? do |key|
          !metadata.key?(key) || metadata[key].blank? || safe_public_id(metadata[key]).present?
        end
    end

    def stripe_value(object, key)
      return object.public_send(key) if object.respond_to?(key)
      if object.respond_to?(:key?)
        return object[key.to_s] if object.key?(key.to_s)
        return object[key.to_sym] if object.key?(key.to_sym)
      end
      return object[key.to_s] if object.respond_to?(:[])

      nil
    end

    def invalid_response
      ServiceResult.failure(
        error: "Stripe returned an invalid reconciliation page.",
        code: "invalid_provider_response"
      )
    end

    def failure(code)
      ServiceResult.failure(
        error: "Stripe reconciliation could not read provider records.",
        code: code
      )
    end
  end
end
