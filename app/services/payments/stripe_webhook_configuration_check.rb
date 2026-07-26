# frozen_string_literal: true

module Payments
  class StripeWebhookConfigurationCheck < ApplicationService
    PROVIDER = "stripe"

    def initialize(config:, public_url: ENV["MCWEB_PUBLIC_URL"])
      @config = config
      @public_url = public_url.to_s.strip
    end

    def call
      endpoint = webhook_endpoint
      checks = [
        check("route", webhook_route_available?, "route_available", "route_missing"),
        check(
          "public_url",
          endpoint.present?,
          "public_url_available",
          "public_url_invalid"
        ),
        check(
          "https",
          endpoint.present? && (!Rails.env.production? || endpoint.start_with?("https://")),
          "https_ready",
          "https_required"
        ),
        check(
          "webhook_secret",
          webhook_secret_valid?,
          "webhook_secret_configured",
          webhook_secret_missing_code
        ),
        check(
          "mode",
          @config.mode_consistent?,
          "mode_aligned",
          "mode_mismatch"
        )
      ]

      ServiceResult.success(
        ready: checks.all? { |item| item.fetch(:ok) },
        endpoint: endpoint,
        required_events: required_events,
        checks: checks
      )
    end

    private

    def check(id, ok, success_code, failure_code)
      {
        id: id,
        ok: ok,
        code: ok ? success_code : failure_code
      }
    end

    def webhook_route_available?
      path = Rails.application.routes.url_helpers.store_webhook_path(provider: PROVIDER)
      route = Rails.application.routes.recognize_path(path, method: :post)
      route[:controller] == "commerce/webhooks" && route[:action] == "create"
    rescue ActionController::RoutingError
      false
    end

    def webhook_endpoint
      uri = URI.parse(public_base_url)
      return unless %w[http https].include?(uri.scheme)
      return if uri.host.blank? || uri.userinfo.present?

      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" unless uri.port == uri.default_port
      "#{origin}#{Rails.application.routes.url_helpers.store_webhook_path(provider: PROVIDER)}"
    rescue URI::InvalidURIError
      nil
    end

    def public_base_url
      return @public_url if @public_url.present?

      options = Rails.application.routes.default_url_options.symbolize_keys
      options = Rails.application.config.action_mailer.default_url_options.symbolize_keys if options[:host].blank?
      protocol = options[:protocol].presence || (Rails.env.production? ? "https" : "http")
      host = options[:host].presence || "localhost"
      port = options[:port].presence
      port ? "#{protocol}://#{host}:#{port}" : "#{protocol}://#{host}"
    end

    def webhook_secret_valid?
      secret = @config.credentials_hash.stringify_keys["webhook_secret"].to_s
      Payments::ProviderConfig::STRIPE_WEBHOOK_SECRET_PATTERN.match?(secret)
    end

    def webhook_secret_missing_code
      if @config.credential_configured?("webhook_secret")
        "webhook_secret_invalid"
      else
        "webhook_secret_missing"
      end
    end

    def required_events
      (
        Payments::StripeProvider::PAYMENT_SUCCEEDED_EVENTS +
        Payments::StripeProvider::PAYMENT_FAILED_EVENTS
      ).uniq.sort
    end
  end
end
