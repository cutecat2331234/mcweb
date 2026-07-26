# frozen_string_literal: true

require "test_helper"

class Mcweb::ProductionEnvironmentTest < ActiveSupport::TestCase
  test "loads secure production settings from explicit environment values" do
    settings = Mcweb::ProductionEnvironment.load!(valid_environment)

    assert_equal "https://community.mcweb.invalid-domain", settings.public_url.to_s
    assert_equal [ "community.mcweb.invalid-domain", "assets.mcweb.invalid-domain" ], settings.allowed_hosts
    assert_equal [ IPAddr.new("127.0.0.1/32"), IPAddr.new("10.20.0.0/16") ], settings.trusted_proxies
    assert_equal :private_s3, settings.storage_service
    assert_equal "smtp.mcweb.invalid-domain", settings.smtp_settings[:address]
    assert_equal 587, settings.smtp_settings[:port]
    assert_equal :plain, settings.smtp_settings[:authentication]
    assert settings.smtp_settings[:enable_starttls_auto]
    assert_not settings.smtp_settings[:ssl]
    assert_equal "McWeb <noreply@mcweb.invalid-domain>", settings.mail_from
    assert_equal(
      { protocol: "https", host: "community.mcweb.invalid-domain" },
      settings.default_url_options
    )

    middleware = ActionDispatch::RemoteIp.new(->(_env) { [ 200, {}, [] ] }, true, settings.trusted_proxies)
    assert_same settings.trusted_proxies, middleware.instance_variable_get(:@proxies)
  end

  test "rejects an insecure or non-origin public URL" do
    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.merge("MCWEB_PUBLIC_URL" => "http://community.mcweb.invalid-domain/path"))
    end

    assert_includes error.message, "MCWEB_PUBLIC_URL"
  end

  test "rejects placeholder production hosts" do
    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.merge("MCWEB_PUBLIC_URL" => "https://example.com"))
    end

    assert_includes error.message, "placeholder"
  end

  test "requires strong runtime encryption and ingress secrets" do
    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(
        valid_environment.merge("SECRET_KEY_BASE" => "generate_with_rails_secret")
      )
    end
    assert_includes error.message, "SECRET_KEY_BASE"

    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(
        valid_environment.merge("LOCKBOX_MASTER_KEY" => "not-hex")
      )
    end
    assert_includes error.message, "LOCKBOX_MASTER_KEY"

    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(
        valid_environment.merge(
          "RAILS_INBOUND_EMAIL_PASSWORD" => "replace_with_a_random_secret"
        )
      )
    end
    assert_includes error.message, "RAILS_INBOUND_EMAIL_PASSWORD"
  end

  test "rejects placeholder database smtp and object storage credentials" do
    {
      "MCWEB_DATABASE_PASSWORD" => "change_me",
      "MCWEB_SMTP_PASSWORD" => "replace_with_smtp_password",
      "MCWEB_S3_SECRET_ACCESS_KEY" => "replace_with_secret_key"
    }.each do |key, value|
      error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
        Mcweb::ProductionEnvironment.load!(valid_environment.merge(key => value))
      end
      assert_includes error.message, key
    end
  end

  test "rejects wildcard hosts and universal trusted proxy ranges" do
    assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.merge("MCWEB_ALLOWED_HOSTS" => "*.mcweb.invalid-domain"))
    end

    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.merge("MCWEB_TRUSTED_PROXIES" => "0.0.0.0/0"))
    end
    assert_includes error.message, "entire Internet"
  end

  test "requires authenticated SMTP credentials and supports an explicit local relay" do
    assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.except("MCWEB_SMTP_PASSWORD"))
    end

    environment = valid_environment.merge("MCWEB_SMTP_AUTHENTICATION" => "none")
      .except("MCWEB_SMTP_USERNAME", "MCWEB_SMTP_PASSWORD")
    settings = Mcweb::ProductionEnvironment.load!(environment)

    assert_nil settings.smtp_settings[:authentication]
  end

  test "requires private object storage and validates static credentials as a pair" do
    assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.merge("MCWEB_ACTIVE_STORAGE_SERVICE" => "local"))
    end

    assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(valid_environment.except("MCWEB_S3_SECRET_ACCESS_KEY"))
    end

    settings = Mcweb::ProductionEnvironment.load!(
      valid_environment.except("MCWEB_S3_ACCESS_KEY_ID", "MCWEB_S3_SECRET_ACCESS_KEY")
    )
    assert_equal :private_s3, settings.storage_service
  end

  test "requires an HTTPS S3-compatible endpoint when one is configured" do
    error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
      Mcweb::ProductionEnvironment.load!(
        valid_environment.merge("MCWEB_S3_ENDPOINT" => "http://object-store.internal")
      )
    end

    assert_includes error.message, "MCWEB_S3_ENDPOINT"
  end

  test "production config applies the same public origin to route generation" do
    production_config = Rails.root.join("config/environments/production.rb").read

    assert_includes(
      production_config,
      "Rails.application.routes.default_url_options = public_url_options"
    )
  end

  test "selected developer production load skips unrelated integrations but keeps the foundation" do
    foundation_environment = valid_environment.slice(
      "SECRET_KEY_BASE",
      "LOCKBOX_MASTER_KEY"
    ).merge(
      "DATABASE_URL" =>
        "postgresql://mcweb:database-password@database.mcweb.invalid-domain/mcweb_production"
    )
    settings = Mcweb::ProductionEnvironment.load_selected!(
      foundation_environment,
      public_origin: false,
      host_authorization: false,
      trusted_proxy_policy: false,
      mail: false,
      storage: false
    )

    assert_nil settings.public_url
    assert_nil settings.allowed_hosts
    assert_nil settings.trusted_proxies
    assert_nil settings.smtp_settings
    assert_nil settings.mail_from
    assert_nil settings.storage_service
  end

  test "selected developer production load still rejects invalid foundation values" do
    environment = valid_environment.slice(
      "SECRET_KEY_BASE",
      "LOCKBOX_MASTER_KEY"
    ).merge(
      "DATABASE_URL" =>
        "postgresql://mcweb:database-password@database.mcweb.invalid-domain/mcweb_production"
    )
    selection = {
      public_origin: false,
      host_authorization: false,
      trusted_proxy_policy: false,
      mail: false,
      storage: false
    }

    {
      "SECRET_KEY_BASE" => "too-short",
      "LOCKBOX_MASTER_KEY" => "not-hex",
      "DATABASE_URL" => "sqlite3:db/production.sqlite3"
    }.each do |key, value|
      error = assert_raises(Mcweb::ProductionEnvironment::InvalidConfiguration) do
        Mcweb::ProductionEnvironment.load_selected!(
          environment.merge(key => value),
          **selection
        )
      end
      assert_includes error.message, key
    end
  end

  private

  def valid_environment
    {
      "MCWEB_PUBLIC_URL" => "https://community.mcweb.invalid-domain",
      "SECRET_KEY_BASE" => "s" * 128,
      "LOCKBOX_MASTER_KEY" => "a" * 64,
      "RAILS_INBOUND_EMAIL_PASSWORD" => "inbound-" + ("p" * 32),
      "MCWEB_DATABASE_HOST" => "database.mcweb.invalid-domain",
      "MCWEB_DATABASE_USERNAME" => "mcweb",
      "MCWEB_DATABASE_PASSWORD" => "database-password",
      "MCWEB_DATABASE_NAME" => "mcweb_production",
      "MCWEB_ALLOWED_HOSTS" => "assets.mcweb.invalid-domain",
      "MCWEB_TRUSTED_PROXIES" => "127.0.0.1/32,10.20.0.0/16",
      "MCWEB_SMTP_ADDRESS" => "smtp.mcweb.invalid-domain",
      "MCWEB_SMTP_PORT" => "587",
      "MCWEB_SMTP_USERNAME" => "smtp-user",
      "MCWEB_SMTP_PASSWORD" => "smtp-password",
      "MCWEB_MAIL_FROM" => "McWeb <noreply@mcweb.invalid-domain>",
      "MCWEB_S3_BUCKET" => "mcweb-production",
      "MCWEB_S3_REGION" => "us-east-1",
      "MCWEB_S3_ACCESS_KEY_ID" => "access-key",
      "MCWEB_S3_SECRET_ACCESS_KEY" => "secret-key"
    }
  end
end
