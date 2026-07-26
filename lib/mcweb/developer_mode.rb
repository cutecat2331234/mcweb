# frozen_string_literal: true

require_relative "local_config"

module Mcweb
  module DeveloperMode
    class InvalidConfiguration < StandardError; end

    Settings = Struct.new(
      :enabled,
      :preset,
      :security,
      :integrations,
      :runtime,
      :auto_login_user,
      keyword_init: true
    ) do
      alias_method :enabled?, :enabled
      alias_method :profile, :preset
    end

    ENV_KEY = "MCWEB_DEVELOPER_MODE"
    PRODUCTION_CONFIRMATION_ENV_KEY =
      "MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION"
    PRODUCTION_CONFIRMATION_VALUE =
      "I_ACCEPT_UNSAFE_DEVELOPER_MODE"
    DEFAULT_CONFIG = Object.new.freeze
    TOP_LEVEL_KEYS = %i[
      enabled
      preset
      security
      integrations
      runtime
      auto_login_user
    ].freeze
    PRESETS = %i[unrestricted].freeze

    SECURITY_ENUMS = {
      transport: %i[inherit http_allowed],
      host_authorization: %i[inherit bypass],
      csrf: %i[inherit bypass],
      csp: %i[inherit disabled],
      frame_protection: %i[inherit disabled],
      cors: %i[inherit allow_all],
      secure_cookies: %i[inherit disabled],
      email_verification: %i[inherit auto_verify],
      two_factor: %i[inherit bypass],
      password_policy: %i[inherit relaxed],
      rate_limits: %i[inherit bypass],
      account_lockout: %i[inherit bypass],
      anti_spam: %i[inherit bypass],
      inbound_webhook_signatures: %i[inherit bypass],
      outbound_url_safety: %i[inherit allow_http_private_networks],
      attachment_malware_scan: %i[inherit assume_clean],
      attachment_quota: %i[inherit bypass],
      plugin_signature: %i[inherit allow_unsigned],
      browser_policy: %i[inherit bypass]
    }.transform_values(&:freeze).freeze

    INTEGRATION_ENUMS = {
      mail: %i[inherit file_capture],
      outbound_webhooks: %i[inherit capture],
      payments: %i[inherit fake],
      web_push: %i[inherit capture],
      minecraft_nodes: %i[inherit simulate],
      remote_skin_lookup: %i[inherit simulate],
      plugin_marketplace: %i[inherit local_only],
      object_storage: %i[inherit local]
    }.transform_values(&:freeze).freeze

    RUNTIME_ENUMS = {
      class_reloading: %i[inherit enabled disabled],
      eager_load: %i[inherit enabled disabled],
      full_error_reports: %i[inherit enabled disabled],
      controller_caching: %i[inherit enabled disabled],
      fragment_caching: %i[inherit enabled disabled],
      asset_cache: %i[inherit enabled disabled],
      asset_minification: %i[inherit enabled disabled],
      response_compression: %i[inherit enabled disabled],
      source_maps: %i[inherit enabled disabled],
      static_asset_far_future_headers: %i[inherit enabled disabled],
      job_backend: %i[inherit async inline],
      log_level: %i[inherit debug info warn error fatal],
      verbose_query_logs: %i[inherit enabled disabled],
      server_timing: %i[inherit enabled disabled],
      template_annotations: %i[inherit enabled disabled]
    }.transform_values(&:freeze).freeze
    RUNTIME_KEYS = (RUNTIME_ENUMS.keys + [ :puma_workers ]).freeze

    UNRESTRICTED_SECURITY = {
      transport: :http_allowed,
      host_authorization: :bypass,
      csrf: :bypass,
      csp: :disabled,
      frame_protection: :disabled,
      cors: :allow_all,
      secure_cookies: :disabled,
      email_verification: :auto_verify,
      two_factor: :bypass,
      password_policy: :relaxed,
      rate_limits: :bypass,
      account_lockout: :bypass,
      anti_spam: :bypass,
      inbound_webhook_signatures: :bypass,
      outbound_url_safety: :allow_http_private_networks,
      attachment_malware_scan: :assume_clean,
      attachment_quota: :bypass,
      plugin_signature: :allow_unsigned,
      browser_policy: :bypass
    }.freeze

    UNRESTRICTED_INTEGRATIONS = {
      mail: :file_capture,
      outbound_webhooks: :capture,
      payments: :fake,
      web_push: :capture,
      minecraft_nodes: :simulate,
      remote_skin_lookup: :simulate,
      plugin_marketplace: :local_only,
      object_storage: :local
    }.freeze

    UNRESTRICTED_RUNTIME = {
      class_reloading: :enabled,
      eager_load: :disabled,
      full_error_reports: :enabled,
      controller_caching: :disabled,
      fragment_caching: :disabled,
      asset_cache: :disabled,
      asset_minification: :disabled,
      response_compression: :disabled,
      source_maps: :enabled,
      static_asset_far_future_headers: :disabled,
      job_backend: :async,
      puma_workers: 0,
      log_level: :debug,
      verbose_query_logs: :enabled,
      server_timing: :enabled,
      template_annotations: :enabled
    }.freeze

    INACTIVE_SECURITY = SECURITY_ENUMS.keys.to_h { |key| [ key, :inherit ] }.freeze
    INACTIVE_INTEGRATIONS = INTEGRATION_ENUMS.keys.to_h { |key| [ key, :inherit ] }.freeze
    INACTIVE_RUNTIME = (
      RUNTIME_ENUMS.keys.to_h { |key| [ key, :inherit ] }.merge(puma_workers: nil)
    ).freeze

    CAPABILITIES = {
      allow_http_transport: [ :transport, :http_allowed ],
      skip_host_authorization: [ :host_authorization, :bypass ],
      skip_csrf: [ :csrf, :bypass ],
      disable_csp: [ :csp, :disabled ],
      disable_frame_protection: [ :frame_protection, :disabled ],
      allow_all_cors: [ :cors, :allow_all ],
      allow_insecure_cookies: [ :secure_cookies, :disabled ],
      skip_email_verification: [ :email_verification, :auto_verify ],
      skip_two_factor: [ :two_factor, :bypass ],
      relax_password_policy: [ :password_policy, :relaxed ],
      skip_rate_limits: [ :rate_limits, :bypass ],
      skip_account_lockout: [ :account_lockout, :bypass ],
      skip_anti_spam: [ :anti_spam, :bypass ],
      skip_inbound_webhook_signatures: [ :inbound_webhook_signatures, :bypass ],
      allow_http_private_networks: [ :outbound_url_safety, :allow_http_private_networks ],
      skip_attachment_malware_scan: [ :attachment_malware_scan, :assume_clean ],
      skip_attachment_scan: [ :attachment_malware_scan, :assume_clean ],
      skip_attachment_quota: [ :attachment_quota, :bypass ],
      allow_unsigned_plugins: [ :plugin_signature, :allow_unsigned ],
      skip_browser_policy: [ :browser_policy, :bypass ]
    }.transform_values(&:freeze).freeze

    class Parser
      def initialize(config:, environment:)
        @config = config
        @environment = environment
      end

      def call
        root = mapping!(@config, "config/local.yml")
        raw_section = root.fetch(:developer_mode, {})
        section = mapping!(raw_section, "developer_mode")
        reject_unknown_keys!(section, TOP_LEVEL_KEYS, "developer_mode")

        configured_enabled = section.key?(:enabled) ?
          yaml_boolean!(section[:enabled], "developer_mode.enabled") :
          false
        enabled = environment_override(configured_enabled)
        preset = enum!(
          section.fetch(:preset, :unrestricted),
          PRESETS,
          "developer_mode.preset"
        )
        security = enum_group(section, :security, SECURITY_ENUMS)
        integrations = enum_group(section, :integrations, INTEGRATION_ENUMS)
        runtime = runtime_group(section)
        auto_login_user = auto_login_user!(section[:auto_login_user])

        if enabled
          build_settings(
            enabled: true,
            preset: preset,
            security: preset_values(preset, :security).merge(security),
            integrations: preset_values(preset, :integrations).merge(integrations),
            runtime: preset_values(preset, :runtime).merge(runtime),
            auto_login_user: auto_login_user
          )
        else
          build_settings(
            enabled: false,
            preset: preset,
            security: INACTIVE_SECURITY,
            integrations: INACTIVE_INTEGRATIONS,
            runtime: INACTIVE_RUNTIME,
            auto_login_user: nil
          )
        end
      end

      private

      def environment_override(configured_enabled)
        return configured_enabled unless @environment.key?(ENV_KEY)

        value = @environment[ENV_KEY].to_s.strip.downcase
        return true if %w[1 true yes on].include?(value)
        return false if %w[0 false no off].include?(value)

        raise InvalidConfiguration,
          "#{ENV_KEY} must be one of: 1, true, yes, on, 0, false, no, off"
      end

      def enum_group(section, group_key, schema)
        return {} unless section.key?(group_key)

        group = mapping!(section[group_key], "developer_mode.#{group_key}")
        reject_unknown_keys!(group, schema.keys, "developer_mode.#{group_key}")
        group.to_h do |key, value|
          [
            key,
            enum!(value, schema.fetch(key), "developer_mode.#{group_key}.#{key}")
          ]
        end
      end

      def runtime_group(section)
        return {} unless section.key?(:runtime)

        runtime = mapping!(section[:runtime], "developer_mode.runtime")
        reject_unknown_keys!(runtime, RUNTIME_KEYS, "developer_mode.runtime")
        runtime.to_h do |key, value|
          if key == :puma_workers
            [ key, nonnegative_integer!(value, "developer_mode.runtime.puma_workers") ]
          else
            [
              key,
              enum!(value, RUNTIME_ENUMS.fetch(key), "developer_mode.runtime.#{key}")
            ]
          end
        end
      end

      def mapping!(value, path)
        unless value.is_a?(Hash)
          raise InvalidConfiguration, "#{path} must be a mapping"
        end

        value.to_h do |key, entry|
          unless key.is_a?(String) || key.is_a?(Symbol)
            raise InvalidConfiguration, "#{path} contains a non-string key"
          end

          [ key.to_sym, entry ]
        end
      end

      def reject_unknown_keys!(mapping, allowed, path)
        unknown = mapping.keys - allowed
        return if unknown.empty?

        raise InvalidConfiguration,
          "#{path} contains unknown #{unknown.one? ? 'key' : 'keys'}: #{unknown.sort.join(', ')}"
      end

      def yaml_boolean!(value, path)
        return value if value == true || value == false

        raise InvalidConfiguration, "#{path} must be a YAML boolean"
      end

      def enum!(value, allowed, path)
        normalized = value.to_s.strip.to_sym if value.is_a?(String) || value.is_a?(Symbol)
        return normalized if normalized && allowed.include?(normalized)

        raise InvalidConfiguration,
          "#{path} must be one of: #{allowed.join(', ')}"
      end

      def nonnegative_integer!(value, path)
        return value if value.is_a?(Integer) && value >= 0

        raise InvalidConfiguration, "#{path} must be a non-negative integer"
      end

      def auto_login_user!(value)
        return nil if value.nil?
        return value.to_s if value.is_a?(Integer) && value.positive?

        if value.is_a?(String)
          identifier = value.strip
          return identifier if !identifier.empty? && identifier.length <= 255
        end

        raise InvalidConfiguration,
          "developer_mode.auto_login_user must be null, a positive integer, or a non-empty string up to 255 characters"
      end

      def preset_values(preset, group)
        case [ preset, group ]
        when [ :unrestricted, :security ]
          UNRESTRICTED_SECURITY
        when [ :unrestricted, :integrations ]
          UNRESTRICTED_INTEGRATIONS
        when [ :unrestricted, :runtime ]
          UNRESTRICTED_RUNTIME
        else
          raise InvalidConfiguration, "unsupported developer mode preset: #{preset}"
        end
      end

      def build_settings(enabled:, preset:, security:, integrations:, runtime:, auto_login_user:)
        Settings.new(
          enabled: enabled,
          preset: preset,
          security: security.dup.freeze,
          integrations: integrations.dup.freeze,
          runtime: runtime.dup.freeze,
          auto_login_user: auto_login_user&.dup&.freeze
        ).freeze
      end
    end

    class << self
      def settings
        @settings ||= parse
      end

      def parse(config: DEFAULT_CONFIG, environment: ENV)
        source = config.equal?(DEFAULT_CONFIG) ? Mcweb::LocalConfig.load_strict : config
        Parser.new(config: source, environment: environment).call
      rescue Psych::SyntaxError => error
        detail = error.respond_to?(:problem) ? error.problem : error.message
        raise InvalidConfiguration,
          "config/local.yml contains invalid YAML: #{detail}"
      end

      def require_production_confirmation!(
        settings: self.settings,
        environment: ENV
      )
        return true unless settings.enabled?
        return true if environment[PRODUCTION_CONFIRMATION_ENV_KEY] ==
          PRODUCTION_CONFIRMATION_VALUE

        raise InvalidConfiguration,
          "Developer Mode in production requires " \
          "#{PRODUCTION_CONFIRMATION_ENV_KEY}=#{PRODUCTION_CONFIRMATION_VALUE} " \
          "exactly"
      end

      def reload!
        Mcweb::LocalConfig.reload!
        @settings = nil
        settings
      end

      def enabled?
        settings.enabled?
      end

      def preset
        settings.preset
      end

      alias_method :profile, :preset

      def security(key = nil)
        key ? settings.security.fetch(key.to_sym) : settings.security
      end

      def integration(key = nil)
        key ? settings.integrations.fetch(key.to_sym) : settings.integrations
      end

      def runtime(key = nil)
        key ? settings.runtime.fetch(key.to_sym) : settings.runtime
      end

      def auto_login_user
        settings.auto_login_user
      end

      def allow?(capability)
        key, expected = CAPABILITIES.fetch(capability.to_sym)
        enabled? && security(key) == expected
      end
    end
  end
end
