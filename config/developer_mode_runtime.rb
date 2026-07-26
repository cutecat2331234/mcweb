# frozen_string_literal: true

require "uri"
require_relative "../lib/mcweb/developer_mode"

module Mcweb
  module DeveloperModeRuntime
    class AllowAllCors
      ALLOWED_METHODS = "GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS"
      EXPOSED_HEADERS =
        "X-Request-Id, X-McWeb-Developer-Mode, Location, Link"

      def initialize(app)
        @app = app
      end

      def call(environment)
        if preflight?(environment)
          response = [ 204, { "Cache-Control" => "no-store" }, [] ]
        else
          response = @app.call(environment)
        end

        status, headers, body = response
        [ status, cors_headers(headers, environment), body ]
      end

      private

      def preflight?(environment)
        environment["REQUEST_METHOD"] == "OPTIONS" &&
          environment["HTTP_ACCESS_CONTROL_REQUEST_METHOD"].to_s != ""
      end

      def cors_headers(headers, environment)
        headers = headers.dup
        origin = environment["HTTP_ORIGIN"].to_s
        request_headers =
          environment["HTTP_ACCESS_CONTROL_REQUEST_HEADERS"].to_s

        headers["Access-Control-Allow-Origin"] = origin.empty? ? "*" : origin
        headers["Access-Control-Allow-Credentials"] = "true" unless origin.empty?
        headers["Access-Control-Allow-Methods"] = ALLOWED_METHODS
        headers["Access-Control-Allow-Headers"] =
          request_headers.empty? ? "*" : request_headers
        headers["Access-Control-Expose-Headers"] = EXPOSED_HEADERS
        if environment["HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK"] == "true"
          headers["Access-Control-Allow-Private-Network"] = "true"
        end
        merge_vary!(
          headers,
          "Origin",
          "Access-Control-Request-Headers",
          "Access-Control-Request-Private-Network"
        )
        headers
      end

      def merge_vary!(headers, *values)
        current = headers["Vary"].to_s.split(",").map(&:strip).reject(&:empty?)
        headers["Vary"] = (current + values).uniq.join(", ")
      end
    end

    STATIC_CACHE_HEADERS = {
      "cache-control" => "public, max-age=31536000"
    }.freeze
    NO_STORE_HEADERS = {
      "cache-control" => "no-store"
    }.freeze
    DEFAULT_URL_OPTIONS = {
      host: "localhost",
      port: 3000
    }.freeze

    class << self
      def apply!(
        config,
        settings: Mcweb::DeveloperMode.settings,
        root: Rails.root,
        routes: Rails.application.routes,
        environment: ENV
      )
        return config unless settings.enabled?

        config.x.mcweb.developer_mode = settings

        apply_runtime(config, settings.runtime)
        apply_request_security(config, settings.security)
        apply_integrations(
          config,
          settings.integrations,
          root: root,
          routes: routes,
          environment: environment
        )
        config
      end

      def production_requirements(settings = Mcweb::DeveloperMode.settings)
        return {
          public_origin: true,
          host_authorization: true,
          trusted_proxy_policy: true,
          mail: true,
          storage: true
        }.freeze unless settings.enabled?

        transport_inherited = settings.security.fetch(:transport) == :inherit
        host_authorization_inherited =
          settings.security.fetch(:host_authorization) == :inherit
        mail_inherited = settings.integrations.fetch(:mail) == :inherit

        {
          public_origin: transport_inherited ||
            host_authorization_inherited ||
            mail_inherited,
          host_authorization: host_authorization_inherited,
          trusted_proxy_policy: transport_inherited,
          mail: mail_inherited,
          storage: settings.integrations.fetch(:object_storage) == :inherit
        }.freeze
      end

      private

      def apply_runtime(config, runtime)
        apply_boolean_option(config, :enable_reloading, runtime.fetch(:class_reloading))
        apply_boolean_option(config, :eager_load, runtime.fetch(:eager_load))
        apply_boolean_option(
          config,
          :consider_all_requests_local,
          runtime.fetch(:full_error_reports)
        )

        apply_controller_cache(config, runtime.fetch(:controller_caching))
        apply_fragment_cache(config, runtime.fetch(:fragment_caching))
        apply_static_cache(
          config,
          asset_cache: runtime.fetch(:asset_cache),
          far_future_headers: runtime.fetch(:static_asset_far_future_headers)
        )
        apply_job_backend(config, runtime.fetch(:job_backend))
        apply_log_level(config, runtime.fetch(:log_level))
        apply_verbose_query_logs(config, runtime.fetch(:verbose_query_logs))
        apply_boolean_option(config, :server_timing, runtime.fetch(:server_timing))
        apply_template_annotations(config, runtime.fetch(:template_annotations))
        apply_response_compression(config, runtime.fetch(:response_compression))
      end

      def apply_request_security(config, security)
        case security.fetch(:csrf)
        when :bypass
          config.action_controller.allow_forgery_protection = false
        when :inherit
          nil
        end

        case security.fetch(:transport)
        when :http_allowed
          config.assume_ssl = false
          config.force_ssl = false
          config.ssl_options = {}
        when :inherit
          nil
        end

        case security.fetch(:host_authorization)
        when :bypass
          config.hosts = []
        when :inherit
          nil
        end

        if security.fetch(:frame_protection) == :disabled
          headers = config.action_dispatch.default_headers.to_h.dup
          headers.delete("X-Frame-Options")
          config.action_dispatch.default_headers = headers
        end

        if security.fetch(:cors) == :allow_all
          config.middleware.insert_before(0, AllowAllCors)
        end

        # McWeb does not currently install a global CSP. Do not create one for
        # Developer Mode, and deliberately leave endpoint-level policies such
        # as attachment download `Content-Security-Policy: sandbox` untouched.
      end

      def apply_integrations(config, integrations, root:, routes:, environment:)
        if integrations.fetch(:object_storage) == :local
          config.active_storage.service = :local
        end

        return unless integrations.fetch(:mail) == :file_capture

        config.action_mailer.delivery_method = :file
        config.action_mailer.file_settings = {
          location: root.join("tmp/developer-mode/mails")
        }
        config.action_mailer.perform_deliveries = true
        config.action_mailer.raise_delivery_errors = true
        config.action_mailer.perform_caching = false

        url_options = developer_url_options(environment)
        config.action_mailer.default_url_options = url_options
        routes.default_url_options = url_options if routes
      end

      def apply_boolean_option(config, key, value)
        case value
        when :enabled
          config.public_send(:"#{key}=", true)
        when :disabled
          config.public_send(:"#{key}=", false)
        when :inherit
          nil
        end
      end

      def apply_controller_cache(config, value)
        case value
        when :enabled
          config.action_controller.perform_caching = true
        when :disabled
          config.action_controller.perform_caching = false
        when :inherit
          nil
        end
      end

      def apply_fragment_cache(config, value)
        case value
        when :enabled
          config.cache_store = :memory_store
        when :disabled
          config.cache_store = :null_store
        when :inherit
          nil
        end
      end

      def apply_static_cache(config, asset_cache:, far_future_headers:)
        return if asset_cache == :inherit && far_future_headers == :inherit

        config.public_file_server.enabled = true
        config.public_file_server.headers =
          if asset_cache == :disabled || far_future_headers == :disabled
            NO_STORE_HEADERS.dup
          else
            STATIC_CACHE_HEADERS.dup
          end
      end

      def apply_job_backend(config, value)
        case value
        when :async, :inline
          config.active_job.queue_adapter = value
        when :inherit
          nil
        end
      end

      def apply_log_level(config, value)
        config.log_level = value unless value == :inherit
      end

      def apply_verbose_query_logs(config, value)
        case value
        when :enabled
          config.active_record.verbose_query_logs = true
          config.active_record.query_log_tags_enabled = true
          config.active_job.verbose_enqueue_logs = true
          config.action_dispatch.verbose_redirect_logs = true
        when :disabled
          config.active_record.verbose_query_logs = false
          config.active_record.query_log_tags_enabled = false
          config.active_job.verbose_enqueue_logs = false
          config.action_dispatch.verbose_redirect_logs = false
        when :inherit
          nil
        end
      end

      def apply_template_annotations(config, value)
        case value
        when :enabled
          config.action_view.annotate_rendered_view_with_filenames = true
        when :disabled
          config.action_view.annotate_rendered_view_with_filenames = false
        when :inherit
          nil
        end
      end

      def apply_response_compression(config, value)
        return unless value == :disabled
        return unless defined?(Rack::Deflater)

        config.middleware.delete(Rack::Deflater)
      end

      def developer_url_options(environment)
        raw_url = environment["MCWEB_PUBLIC_URL"].to_s.strip
        return DEFAULT_URL_OPTIONS.dup if raw_url.empty?

        uri = URI.parse(raw_url)
        valid = uri.is_a?(URI::HTTP) &&
          uri.host.to_s != "" &&
          uri.userinfo.nil? &&
          uri.query.nil? &&
          uri.fragment.nil? &&
          [ "", "/" ].include?(uri.path.to_s)
        return DEFAULT_URL_OPTIONS.dup unless valid

        {
          protocol: uri.scheme,
          host: uri.host,
          port: default_port?(uri) ? nil : uri.port
        }.compact
      rescue URI::InvalidURIError
        DEFAULT_URL_OPTIONS.dup
      end

      def default_port?(uri)
        (uri.is_a?(URI::HTTPS) && uri.port == 443) ||
          (uri.is_a?(URI::HTTP) && !uri.is_a?(URI::HTTPS) && uri.port == 80)
      end
    end
  end
end
