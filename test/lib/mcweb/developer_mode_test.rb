# frozen_string_literal: true

require "test_helper"

class Mcweb::DeveloperModeTest < ActiveSupport::TestCase
  test "defaults to disabled when the section is absent" do
    settings = parse({})

    assert_not settings.enabled?
    assert_equal :unrestricted, settings.preset
    assert_equal :production, settings.runtime_profile
    assert_equal :inherit, settings.security.fetch(:email_verification)
    assert_equal :inherit, settings.integrations.fetch(:payments)
    assert_equal :inherit, settings.runtime.fetch(:job_backend)
    assert_nil settings.runtime.fetch(:puma_workers)
    assert_nil settings.auto_login_user
  end

  test "loads the unrestricted preset and applies typed overrides" do
    settings = parse(
      developer_mode: {
        enabled: true,
        preset: "unrestricted",
        security: {
          rate_limits: "inherit",
          email_verification: "auto_verify"
        },
        integrations: {
          payments: "inherit"
        },
        runtime: {
          job_backend: "inline",
          puma_workers: 2
        },
        auto_login_user: " owner@example.test "
      }
    )

    assert settings.enabled?
    assert_equal :unrestricted, settings.profile
    assert_equal :debug, settings.runtime_profile
    assert_equal :inherit, settings.security.fetch(:rate_limits)
    assert_equal :auto_verify, settings.security.fetch(:email_verification)
    assert_equal :bypass, settings.security.fetch(:two_factor)
    assert_equal :bypass, settings.security.fetch(:browser_policy)
    assert_equal :inherit, settings.integrations.fetch(:payments)
    assert_equal :file_capture, settings.integrations.fetch(:mail)
    assert_equal :inline, settings.runtime.fetch(:job_backend)
    assert_equal 2, settings.runtime.fetch(:puma_workers)
    assert_equal :disabled, settings.runtime.fetch(:eager_load)
    assert_equal "owner@example.test", settings.auto_login_user
  end

  test "fast preview keeps developer integrations while enabling production-like runtime" do
    settings = parse(
      developer_mode: {
        enabled: true,
        runtime_profile: "fast_preview"
      }
    )

    assert settings.enabled?
    assert_equal :fast_preview, settings.runtime_profile
    assert_equal :bypass, settings.security.fetch(:two_factor)
    assert_equal :fake, settings.integrations.fetch(:payments)
    assert_equal :disabled, settings.runtime.fetch(:class_reloading)
    assert_equal :enabled, settings.runtime.fetch(:eager_load)
    assert_equal :enabled, settings.runtime.fetch(:controller_caching)
    assert_equal :enabled, settings.runtime.fetch(:fragment_caching)
    assert_equal :enabled, settings.runtime.fetch(:asset_minification)
    assert_equal :disabled, settings.runtime.fetch(:source_maps)
    assert_equal :enabled, settings.runtime.fetch(:response_compression)
    assert_equal :info, settings.runtime.fetch(:log_level)
  end

  test "runtime profile accepts a strict environment override" do
    settings = parse(
      { developer_mode: { enabled: true } },
      environment: { "MCWEB_RUNTIME_PROFILE" => "fast_preview" }
    )

    assert_equal :fast_preview, settings.runtime_profile
    assert_equal :enabled, settings.runtime.fetch(:eager_load)

    error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
      parse(
        { developer_mode: { enabled: true } },
        environment: { "MCWEB_RUNTIME_PROFILE" => "turbo" }
      )
    end
    assert_includes error.message, "MCWEB_RUNTIME_PROFILE"
  end

  test "validates overrides even while the mode is disabled" do
    error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
      parse(
        developer_mode: {
          enabled: false,
          security: { rate_limits: "unlimited-ish" }
        }
      )
    end

    assert_includes error.message, "developer_mode.security.rate_limits"
  end

  test "rejects unknown keys at every schema level" do
    {
      { developer_mode: { enabled: true, surprise: true } } =>
        "developer_mode contains unknown key: surprise",
      { developer_mode: { enabled: true, security: { surprise: "bypass" } } } =>
        "developer_mode.security contains unknown key: surprise",
      { developer_mode: { enabled: true, integrations: { surprise: "fake" } } } =>
        "developer_mode.integrations contains unknown key: surprise",
      { developer_mode: { enabled: true, runtime: { surprise: "disabled" } } } =>
        "developer_mode.runtime contains unknown key: surprise"
    }.each do |config, expected_message|
      error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
        parse(config)
      end

      assert_equal expected_message, error.message
    end
  end

  test "rejects unsupported presets and enum values" do
    {
      { developer_mode: { enabled: true, preset: "fast_and_loose" } } =>
        "developer_mode.preset",
      { developer_mode: { enabled: true, runtime_profile: "fast_and_loose" } } =>
        "developer_mode.runtime_profile",
      { developer_mode: { enabled: true, security: { csrf: "off" } } } =>
        "developer_mode.security.csrf",
      { developer_mode: { enabled: true, integrations: { payments: "stripe" } } } =>
        "developer_mode.integrations.payments",
      { developer_mode: { enabled: true, runtime: { log_level: "trace" } } } =>
        "developer_mode.runtime.log_level"
    }.each do |config, expected_path|
      error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
        parse(config)
      end

      assert_includes error.message, expected_path
      assert_includes error.message, "must be one of"
    end
  end

  test "requires a real YAML boolean for the config switch" do
    error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
      parse(developer_mode: { enabled: "true" })
    end

    assert_equal "developer_mode.enabled must be a YAML boolean", error.message
  end

  test "strictly validates mappings integers and auto login identifiers" do
    invalid_configs = [
      { developer_mode: true },
      { developer_mode: { security: nil } },
      { developer_mode: { integrations: [] } },
      { developer_mode: { runtime: { puma_workers: "0" } } },
      { developer_mode: { auto_login_user: false } },
      { developer_mode: { auto_login_user: " " } }
    ]

    invalid_configs.each do |config|
      assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
        parse(config)
      end
    end
  end

  test "supports a strict environment override" do
    enabled = parse({}, environment: { "MCWEB_DEVELOPER_MODE" => "yes" })
    disabled = parse(
      { developer_mode: { enabled: true } },
      environment: { "MCWEB_DEVELOPER_MODE" => "off" }
    )

    assert enabled.enabled?
    assert_not disabled.enabled?

    error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
      parse({}, environment: { "MCWEB_DEVELOPER_MODE" => "sometimes" })
    end
    assert_includes error.message, "MCWEB_DEVELOPER_MODE"
  end

  test "production activation requires an exact independent confirmation" do
    disabled = parse({})
    enabled = parse(developer_mode: { enabled: true })
    confirmation_key =
      Mcweb::DeveloperMode::PRODUCTION_CONFIRMATION_ENV_KEY
    confirmation_value =
      Mcweb::DeveloperMode::PRODUCTION_CONFIRMATION_VALUE

    assert Mcweb::DeveloperMode.require_production_confirmation!(
      settings: disabled,
      environment: {}
    )
    assert Mcweb::DeveloperMode.require_production_confirmation!(
      settings: enabled,
      environment: { confirmation_key => confirmation_value }
    )

    [ {}, { confirmation_key => "true" }, { confirmation_key => confirmation_value.downcase } ].each do |environment|
      error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
        Mcweb::DeveloperMode.require_production_confirmation!(
          settings: enabled,
          environment: environment
        )
      end
      assert_includes error.message, confirmation_key
      assert_includes error.message, confirmation_value
    end
  end

  test "surfaces malformed local YAML instead of silently disabling the mode" do
    original_path = ENV["MCWEB_LOCAL_CONFIG_PATH"]
    directory = Dir.mktmpdir
    ENV["MCWEB_LOCAL_CONFIG_PATH"] = File.join(directory, "local.yml")
    File.write(ENV.fetch("MCWEB_LOCAL_CONFIG_PATH"), "developer_mode:\n  enabled: [\n")

    error = assert_raises(Mcweb::DeveloperMode::InvalidConfiguration) do
      Mcweb::DeveloperMode.parse(environment: {})
    end

    assert_includes error.message, "config/local.yml contains invalid YAML"
  ensure
    if original_path
      ENV["MCWEB_LOCAL_CONFIG_PATH"] = original_path
    else
      ENV.delete("MCWEB_LOCAL_CONFIG_PATH")
    end
    Mcweb::LocalConfig.reload!
    Pathname(directory).rmtree if directory && Pathname(directory).exist?
  end

  test "exposes one immutable query interface" do
    configured = parse(
      developer_mode: {
        enabled: true,
        security: { rate_limits: "inherit" },
        integrations: { payments: "fake" },
        runtime: { job_backend: "inline" },
        auto_login_user: 42
      }
    )

    previous_settings = Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, configured)
    begin
      assert Mcweb::DeveloperMode.enabled?
      assert_equal :unrestricted, Mcweb::DeveloperMode.preset
      assert_equal :unrestricted, Mcweb::DeveloperMode.profile
      assert_equal :debug, Mcweb::DeveloperMode.runtime_profile
      assert_equal :auto_verify, Mcweb::DeveloperMode.security(:email_verification)
      assert_equal :fake, Mcweb::DeveloperMode.integration(:payments)
      assert_equal :inline, Mcweb::DeveloperMode.runtime(:job_backend)
      assert_equal "42", Mcweb::DeveloperMode.auto_login_user
      assert Mcweb::DeveloperMode.allow?(:skip_email_verification)
      assert Mcweb::DeveloperMode.allow?(:skip_browser_policy)
      assert_not Mcweb::DeveloperMode.allow?(:skip_rate_limits)
      assert_raises(KeyError) { Mcweb::DeveloperMode.allow?(:unknown_capability) }
    ensure
      Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
    end

    assert_predicate configured, :frozen?
    assert_predicate configured.security, :frozen?
    assert_raises(FrozenError) { configured.runtime[:job_backend] = :async }
  end

  test "every declared security capability has enabled disabled and inherit pairs" do
    unrestricted = parse(developer_mode: { enabled: true })
    disabled = parse(developer_mode: { enabled: false })

    with_settings(unrestricted) do
      Mcweb::DeveloperMode::CAPABILITIES.each_key do |capability|
        assert Mcweb::DeveloperMode.allow?(capability),
          "#{capability} should be active in unrestricted mode"
      end
    end

    with_settings(disabled) do
      Mcweb::DeveloperMode::CAPABILITIES.each_key do |capability|
        assert_not Mcweb::DeveloperMode.allow?(capability),
          "#{capability} must preserve normal behavior while disabled"
      end
    end

    Mcweb::DeveloperMode::CAPABILITIES.each do |capability, (setting, _value)|
      inherited = parse(
        developer_mode: {
          enabled: true,
          security: { setting => "inherit" }
        }
      )
      with_settings(inherited) do
        assert_not Mcweb::DeveloperMode.allow?(capability),
          "#{capability} must preserve normal behavior when inherited"
      end
    end
  end

  test "global CSP is explicit and Developer Mode only disables the global policy" do
    source = Rails.root.join(
      "config/initializers/content_security_policy.rb"
    ).read

    assert_includes source,
      "unless Mcweb::DeveloperMode.allow?(:disable_csp)"
    assert_includes source, "policy.default_src :self"
    assert_includes source, "policy.object_src :none"
    assert_includes source, "policy.frame_ancestors :self"
    assert_includes source, "Endpoint-specific sandbox policies"
  end

  private

  def with_settings(settings)
    previous_settings =
      Mcweb::DeveloperMode.instance_variable_get(:@settings)
    Mcweb::DeveloperMode.instance_variable_set(:@settings, settings)
    yield
  ensure
    Mcweb::DeveloperMode.instance_variable_set(:@settings, previous_settings)
  end

  def parse(config = nil, environment: {}, **config_keywords)
    config = config_keywords if config.nil?
    Mcweb::DeveloperMode.parse(config: config, environment: environment)
  end
end
