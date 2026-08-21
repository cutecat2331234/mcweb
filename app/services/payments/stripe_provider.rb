# frozen_string_literal: true

module Payments
  class StripeProvider < Provider
    WEBHOOK_TOLERANCE_SECONDS = 5.minutes.to_i
    PAYMENT_SUCCEEDED_EVENTS = %w[
      checkout.session.completed
      checkout.session.async_payment_succeeded
      payment_intent.succeeded
    ].freeze
    PAYMENT_FAILED_EVENTS = %w[
      checkout.session.expired
      checkout.session.async_payment_failed
      payment_intent.payment_failed
      payment_intent.canceled
    ].freeze
    RETRYABLE_PAYMENT_FAILURE_EVENTS = %w[
      payment_intent.payment_failed
    ].freeze
    DISPUTE_EVENTS = %w[
      charge.dispute.created
      charge.dispute.updated
      charge.dispute.closed
      charge.dispute.funds_withdrawn
      charge.dispute.funds_reinstated
    ].freeze
    CHECKOUT_SESSION_EVENTS = (
      PAYMENT_SUCCEEDED_EVENTS + PAYMENT_FAILED_EVENTS
    ).grep(/\Acheckout\.session\./).freeze

    def initialize(client: nil)
      @client = client
    end

    def create_payment(payment_record, return_url_base: nil)
      config = Payments::ProviderConfig.checkout_config_for("stripe")
      return ServiceResult.failure(error: :stripe_is_not_enabled_or_fully_configured) unless config

      record = Payments::Record.includes(:order).find(payment_record.id)
      validation_error = checkout_record_error(record)
      return ServiceResult.failure(error: validation_error) if validation_error
      mode_error = ensure_checkout_provider_mode(record, config)
      return mode_error if mode_error

      return_urls = checkout_return_urls(record.order, return_url_base)
      return return_urls if return_urls.is_a?(ServiceResult)

      idempotency_key = checkout_idempotency_key(record)
      attempt = record.attempts.create!(
        status: "processing",
        request_data: {
          operation: "checkout_session.create",
          idempotency_key: idempotency_key,
          amount_cents: record.amount_cents,
          currency: record.currency
        }
      )

      session = stripe_client(config).v1.checkout.sessions.create(
        checkout_session_params(record, return_urls),
        { idempotency_key: idempotency_key }
      )
      session_error = checkout_session_error(session, config)
      raise Stripe::APIError, session_error if session_error

      session_id = stripe_value(session, :id).to_s
      checkout_url = stripe_value(session, :url).to_s
      livemode = stripe_value(session, :livemode)

      record.with_lock do
        record.update!(
          provider_payment_id: session_id,
          metadata: record.metadata.merge(
            "payment_record_id" => record.id.to_s,
            "stripe_checkout_session_id" => session_id,
            "stripe_checkout_livemode" => livemode,
            "stripe_checkout_idempotency_key" => idempotency_key
          )
        )
      end
      attempt.update!(
        status: "succeeded",
        response_data: {
          provider_payment_id: session_id,
          livemode: livemode
        }
      )

      ServiceResult.success(payment_record: record.reload, checkout_url: checkout_url)
    rescue Stripe::StripeError => error
      mark_attempt_failed(attempt, error)
      ServiceResult.failure(
        error: :stripe_could_not_create_the_payment_session_please_try_again,
        code: stripe_error_code(error)
      )
    end

    def verify_webhook_signature(payload:, signature:, headers: {})
      secret = webhook_secret
      stripe_signature = headers["HTTP_STRIPE_SIGNATURE"].to_s.presence || signature.to_s
      return false if secret.blank? || stripe_signature.blank?

      Stripe::Webhook.construct_event(
        payload,
        stripe_signature,
        secret,
        tolerance: WEBHOOK_TOLERANCE_SECONDS
      )
      true
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      false
    end

    def process_webhook_event(event)
      event_type = event.event_type.to_s
      payload_type = event.payload.to_h["type"].to_s
      if payload_type.present? && !ActiveSupport::SecurityUtils.secure_compare(payload_type, event_type)
        return ServiceResult.failure(error: :stripe_event_type_mismatch, code: "event_mismatch")
      end

      if PAYMENT_SUCCEEDED_EVENTS.include?(event_type)
        process_payment_success(event)
      elsif PAYMENT_FAILED_EVENTS.include?(event_type)
        process_payment_failure(event)
      elsif DISPUTE_EVENTS.include?(event_type)
        process_dispute_event(event)
      else
        ServiceResult.success(ignored: true)
      end
    end

    def process_refund(refund)
      config = Payments::ProviderConfig.checkout_config_for("stripe")
      unless config
        return ServiceResult.failure(
          error: :stripe_is_not_enabled_or_fully_configured,
          code: "provider_configuration_missing"
        )
      end
      unless refund.payment_record.provider_mode == config.effective_mode
        return ServiceResult.failure(
          error: :the_payment_stripe_environment_is_unknown_or_differs_from_the_active_provider,
          code: "environment_mismatch"
        )
      end

      payment_intent_id = stripe_payment_intent_id(refund.payment_record)
      unless payment_intent_id.match?(/\Api_[A-Za-z0-9_]+\z/)
        return ServiceResult.failure(
          error: :stripe_payment_intent_is_unavailable_for_this_payment,
          code: "provider_payment_missing"
        )
      end

      provider_refund =
        if refund.provider_refund_id.present?
          stripe_client(config).v1.refunds.retrieve(refund.provider_refund_id)
        else
          stripe_client(config).v1.refunds.create(
            {
              payment_intent: payment_intent_id,
              amount: refund.amount_cents,
              reason: ("requested_by_customer" if refund.requested_by_customer?),
              metadata: {
                mcweb_refund_id: refund.id.to_s,
                payment_record_id: refund.payment_record_id.to_s,
                order_public_id: refund.order.public_id
              }.compact
            },
            { idempotency_key: refund_idempotency_key(refund) }
          )
        end

      refund_result(
        provider_refund,
        refund,
        payment_intent_id,
        expected_mode: config.effective_mode
      )
    rescue Stripe::StripeError => error
      ServiceResult.failure(
        error: :stripe_could_not_process_the_refund,
        code: stripe_error_code(error),
        value: {
          provider_refund_id: refund.provider_refund_id,
          provider_status: "error",
          provider_error_code: stripe_error_code(error)
        }
      )
    end

    private

    def process_dispute_event(event)
      object = stripe_event_object(event)
      payment_record = locate_dispute_payment_record(object)
      return ServiceResult.failure(error: :payment_not_found, code: "payment_not_found") unless payment_record

      evidence_details = object.fetch("evidence_details", {}).to_h.stringify_keys
      Commerce::Disputes::ApplyChannelEvent.call(
        provider: "stripe",
        provider_event_id: event.event_id,
        provider_dispute_id: object["id"],
        payment_record: payment_record,
        event_type: event.event_type,
        provider_status: normalized_dispute_status(event.event_type, object["status"]),
        amount_cents: object["amount"],
        currency: object["currency"],
        occurred_at: event.payload["created"] || event.created_at,
        sequence: event.payload["created"],
        evidence_due_at: evidence_details["due_by"],
        risk_level: dispute_risk_level(object),
        reason_code: object["reason"],
        kind: "chargeback",
        payload_digest: event.payload_digest,
        webhook_event: event
      )
    end

    def locate_dispute_payment_record(object)
      metadata_id = object.fetch("metadata", {}).to_h.stringify_keys["payment_record_id"]
      payment_intent = stripe_identifier(object["payment_intent"])

      Payments::Record.includes(:order).find_by(id: metadata_id) ||
        Payments::Record.includes(:order).find_by(
          provider: "stripe",
          provider_payment_id: payment_intent
        ) ||
        Payments::Record.includes(:order)
          .where(provider: "stripe")
          .where("metadata ->> 'stripe_payment_intent_id' = ?", payment_intent)
          .first
    end

    def normalized_dispute_status(event_type, provider_status)
      return "won" if event_type == "charge.dispute.funds_reinstated"
      return "lost" if event_type == "charge.dispute.funds_withdrawn"

      provider_status.to_s
    end

    def dispute_risk_level(object)
      return "critical" if object["reason"].to_s == "fraudulent"

      "high"
    end

    def stripe_identifier(value)
      value.is_a?(Hash) ? value.stringify_keys["id"].to_s : value.to_s
    end

    def process_payment_success(event)
      object = stripe_event_object(event)
      payment_record = locate_payment_record(event)
      return ServiceResult.failure(error: :payment_not_found, code: "payment_not_found") unless payment_record

      validation_error = payment_event_error(
        payment_record: payment_record,
        object: object,
        event_type: event.event_type,
        succeeded: true
      )
      return validation_error if validation_error.is_a?(ServiceResult)

      if checkout_session_event?(event.event_type) && object["payment_status"] != "paid"
        return ServiceResult.success(deferred: true) if event.event_type == "checkout.session.completed"

        return ServiceResult.failure(error: :stripe_checkout_session_is_not_paid, code: "payment_not_paid")
      end

      payment_intent_id = payment_intent_id_from(object, event.event_type)
      metadata = {
        "webhook_event_id" => event.event_id,
        "stripe_event_type" => event.event_type,
        "stripe_livemode" => object["livemode"],
        "stripe_payment_intent_id" => payment_intent_id
      }.compact

      confirmation = Commerce::ConfirmPayment.call(
        payment_record: payment_record,
        provider_payment_id: payment_record.provider_payment_id,
        metadata: metadata,
        webhook_event: event
      )

      if confirmation.failure? && confirmation.value.is_a?(Hash) && confirmation.value[:orphaned]
        return ServiceResult.success(
          payment_record: payment_record.reload,
          orphaned: true,
          late_payment_case: confirmation.value[:late_payment_case]
        )
      end

      confirmation
    end

    def process_payment_failure(event)
      object = stripe_event_object(event)
      payment_record = locate_payment_record(event)
      return ServiceResult.failure(error: :payment_not_found, code: "payment_not_found") unless payment_record

      validation_error = payment_event_error(
        payment_record: payment_record,
        object: object,
        event_type: event.event_type,
        succeeded: false
      )
      return validation_error if validation_error.is_a?(ServiceResult)

      metadata = {
        "stripe_failure_event_id" => event.event_id,
        "stripe_failure_event_type" => event.event_type,
        "stripe_payment_intent_id" => payment_intent_id_from(object, event.event_type)
      }.compact
      if RETRYABLE_PAYMENT_FAILURE_EVENTS.include?(event.event_type)
        payment_record.with_lock do
          if payment_record.pending? || payment_record.processing?
            payment_record.update!(metadata: payment_record.metadata.merge(metadata))
          end
        end
      else
        payment_record.mark_failed!(metadata:)
      end

      ServiceResult.success(payment_record: payment_record.reload)
    end

    def payment_event_error(payment_record:, object:, event_type:, succeeded:)
      return ServiceResult.failure(error: :stripe_event_object_is_missing, code: "object_missing") if object.empty?
      return ServiceResult.failure(error: :payment_provider_mismatch, code: "provider_mismatch") unless payment_record.provider == "stripe"

      config = Payments::ProviderConfig.checkout_config_for("stripe")
      return ServiceResult.failure(error: :stripe_configuration_is_unavailable, code: "provider_unavailable") unless config

      if payment_record.provider_mode.blank? ||
          payment_record.provider_mode != config.effective_mode
        return ServiceResult.failure(
          error: :stripe_payment_environment_mismatch,
          code: "environment_mismatch"
        )
      end

      expected_livemode = payment_record.provider_mode == "live"
      unless object["livemode"] == expected_livemode
        return ServiceResult.failure(error: :stripe_environment_mismatch, code: "environment_mismatch")
      end

      metadata = object.fetch("metadata", {}).to_h.stringify_keys
      unless metadata["payment_record_id"].to_s == payment_record.id.to_s &&
          metadata["order_public_id"].to_s == payment_record.order.public_id.to_s
        return ServiceResult.failure(error: :stripe_payment_metadata_mismatch, code: "metadata_mismatch")
      end

      if checkout_session_event?(event_type)
        unless object["id"].to_s == payment_record.provider_payment_id.to_s &&
            object["client_reference_id"].to_s == payment_record.order.public_id.to_s
          return ServiceResult.failure(error: :stripe_checkout_session_mismatch, code: "session_mismatch")
        end
        provider_amount = object["amount_total"]
      else
        known_payment_intent = payment_record.metadata["stripe_payment_intent_id"].to_s
        if known_payment_intent.present? && object["id"].to_s != known_payment_intent
          return ServiceResult.failure(error: :stripe_payment_intent_mismatch, code: "payment_intent_mismatch")
        end
        provider_amount = succeeded ? object["amount_received"] : object["amount"]
        provider_amount ||= object["amount"]
      end

      unless provider_amount.to_i == payment_record.amount_cents &&
          object["currency"].to_s.casecmp?(payment_record.currency.to_s)
        return ServiceResult.failure(error: :stripe_payment_amount_or_currency_mismatch, code: "amount_mismatch")
      end

      nil
    end

    def locate_payment_record(event)
      object = stripe_event_object(event)
      metadata_id = object.fetch("metadata", {}).to_h.stringify_keys["payment_record_id"]

      Payments::Record.includes(:order).find_by(id: metadata_id) ||
        Payments::Record.includes(:order).find_by(
          provider: "stripe",
          provider_payment_id: object["id"]
        )
    end

    def stripe_event_object(event)
      event.payload.to_h.dig("data", "object").to_h.deep_stringify_keys
    end

    def checkout_session_event?(event_type)
      CHECKOUT_SESSION_EVENTS.include?(event_type.to_s)
    end

    def payment_intent_id_from(object, event_type)
      value =
        if checkout_session_event?(event_type)
          object["payment_intent"]
        else
          object["id"]
        end

      value.is_a?(Hash) ? value["id"].to_s.presence : value.to_s.presence
    end

    def checkout_record_error(record)
      return "Payment provider mismatch." unless record.provider == "stripe"
      return "Payment is no longer pending." unless record.pending? || record.processing?
      return "Payment amount must be greater than zero." unless record.amount_cents.positive?
      return "Payment amount no longer matches the order." unless record.amount_cents == record.order.total_cents
      return "Payment currency no longer matches the order." unless record.currency.to_s.casecmp?(record.order.currency.to_s)

      nil
    end

    def checkout_session_params(record, return_urls)
      metadata = {
        payment_record_id: record.id.to_s,
        order_public_id: record.order.public_id
      }

      {
        mode: "payment",
        client_reference_id: record.order.public_id,
        success_url: return_urls.fetch(:success_url),
        cancel_url: return_urls.fetch(:cancel_url),
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency: record.currency.downcase,
              unit_amount: record.amount_cents,
              product_data: {
                name: "Order #{record.order.order_number}"
              }
            }
          }
        ],
        metadata: metadata,
        payment_intent_data: {
          metadata: metadata
        }
      }
    end

    def checkout_return_urls(order, supplied_base)
      base = ENV["MCWEB_PUBLIC_URL"].presence || supplied_base.to_s.presence
      base ||= default_public_base_url
      uri = URI.parse(base.to_s)

      unless %w[http https].include?(uri.scheme) && uri.host.present? && uri.userinfo.blank?
        return ServiceResult.failure(error: :the_public_checkout_return_url_is_invalid)
      end
      if Rails.env.production? && uri.scheme != "https"
        return ServiceResult.failure(error: :the_public_checkout_return_url_must_use_https_in_production)
      end

      normalized_base = "#{uri.scheme}://#{uri.host}"
      normalized_base += ":#{uri.port}" unless uri.port == uri.default_port
      order_path = Rails.application.routes.url_helpers.store_order_path(order.public_id)

      {
        success_url: "#{normalized_base}#{order_path}?payment=success&session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "#{normalized_base}#{order_path}?payment=cancelled"
      }
    rescue URI::InvalidURIError
      ServiceResult.failure(error: :the_public_checkout_return_url_is_invalid)
    end

    def default_public_base_url
      options = Rails.application.config.action_mailer.default_url_options.symbolize_keys
      protocol = options[:protocol].presence || (Rails.env.production? ? "https" : "http")
      port = options[:port].presence
      base = "#{protocol}://#{options[:host].presence || 'localhost'}"
      port ? "#{base}:#{port}" : base
    end

    def checkout_session_error(session, config)
      session_id = stripe_value(session, :id).to_s
      checkout_url = stripe_value(session, :url).to_s
      livemode = stripe_value(session, :livemode)
      return "Stripe did not return a Checkout Session ID." unless session_id.start_with?("cs_")
      return "Stripe did not return a secure Checkout URL." unless secure_checkout_url?(checkout_url)
      return "Stripe Checkout Session environment mismatch." unless livemode == live_secret_key?(config)

      nil
    end

    def secure_checkout_url?(value)
      uri = URI.parse(value)
      uri.scheme == "https" && uri.host.present? && uri.userinfo.blank?
    rescue URI::InvalidURIError
      false
    end

    def checkout_idempotency_key(record)
      "mcweb:checkout:payment:#{record.id}:v1"
    end

    def refund_idempotency_key(refund)
      "mcweb:refund:#{refund.id}:v1"
    end

    def refund_result(provider_refund, refund, payment_intent_id, expected_mode:)
      provider_refund_id = stripe_value(provider_refund, :id).to_s
      provider_status = stripe_value(provider_refund, :status).to_s
      provider_amount = stripe_value(provider_refund, :amount).to_i
      provider_currency = stripe_value(provider_refund, :currency).to_s
      provider_payment_intent = stripe_value(provider_refund, :payment_intent).to_s
      provider_livemode = stripe_value(provider_refund, :livemode)
      provider_error_code = stripe_value(provider_refund, :failure_reason).to_s.presence
      details = {
        provider_refund_id: provider_refund_id,
        provider_status: provider_status,
        provider_error_code: provider_error_code,
        provider_metadata: {
          "payment_intent_id" => provider_payment_intent,
          "livemode" => provider_livemode,
          "charge_id" => stripe_value(provider_refund, :charge).to_s.presence,
          "balance_transaction_id" => stripe_value(provider_refund, :balance_transaction).to_s.presence
        }.compact
      }

      unless provider_refund_id.start_with?("re_") &&
          provider_livemode == (expected_mode == "live") &&
          provider_amount == refund.amount_cents &&
          provider_currency.casecmp?(refund.payment_record.currency) &&
          provider_payment_intent == payment_intent_id
        return ServiceResult.failure(
          error: :stripe_refund_response_does_not_match_the_local_refund,
          code: "provider_mismatch",
          value: details
        )
      end

      if provider_status == "succeeded"
        ServiceResult.success(details)
      elsif %w[pending requires_action].include?(provider_status)
        ServiceResult.failure(
          error: :stripe_refund_is_still_pending,
          code: "provider_pending",
          value: details
        )
      else
        ServiceResult.failure(
          error: :stripe_refund_failed,
          code: provider_error_code || "provider_refund_failed",
          value: details
        )
      end
    end

    def stripe_payment_intent_id(payment_record)
      payment_record.metadata["stripe_payment_intent_id"].to_s.presence ||
        payment_record.provider_payment_id.to_s.presence
    end

    def ensure_checkout_provider_mode(record, config)
      result = nil
      record.with_lock do
        if record.provider_mode.blank?
          record.update!(provider_mode: config.effective_mode)
        elsif record.provider_mode != config.effective_mode
          result = ServiceResult.failure(
            error: :the_payment_stripe_environment_differs_from_the_active_provider,
            code: "environment_mismatch"
          )
        end
      end
      result
    end

    def stripe_client(config)
      @client ||= Stripe::StripeClient.new(config.credentials_hash.stringify_keys.fetch("secret_key"))
    end

    def live_secret_key?(config)
      config.credentials_hash.stringify_keys.fetch("secret_key").match?(/\A(?:sk|rk)_live_/)
    end

    def webhook_secret
      Payments::ProviderConfig.find_by(provider: "stripe")&.credentials_hash&.stringify_keys&.dig("webhook_secret")
    end

    def stripe_value(object, key)
      if object.respond_to?(:[])
        return object[key.to_s] if object.respond_to?(:key?) && object.key?(key.to_s)
        return object[key.to_sym] if object.respond_to?(:key?) && object.key?(key.to_sym)

        value = object[key.to_s]
        value.nil? ? object[key.to_sym] : value
      elsif object.respond_to?(key)
        object.public_send(key)
      end
    end

    def stripe_error_code(error)
      code = error.respond_to?(:code) ? error.code.to_s.presence : nil
      code || error.class.name.demodulize.underscore
    end

    def mark_attempt_failed(attempt, error)
      return unless attempt&.persisted?

      attempt.update!(
        status: "failed",
        response_data: { error_code: stripe_error_code(error) }
      )
    rescue ActiveRecord::ActiveRecordError
      nil
    end
  end
end
