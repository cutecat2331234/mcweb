# frozen_string_literal: true

require "test_helper"
require "json"
require "open3"
require "rbconfig"
require_relative "../../../config/developer_mode_runtime"

class Mcweb::DeveloperModeRuntimeTest < ActiveSupport::TestCase
  class FakeMiddleware
    attr_reader :deleted, :inserted

    def initialize
      @deleted = []
      @inserted = []
    end

    def delete(middleware)
      @deleted << middleware
    end

    def insert_before(index, middleware, *arguments)
      @inserted << [ index, middleware, arguments ]
    end
  end

  class FakeRoutes
    attr_accessor :default_url_options
  end

  test "disabled mode leaves the environment configuration untouched" do
    config = production_like_config
    routes = FakeRoutes.new
    routes.default_url_options = { protocol: "https", host: "community.example" }
    before = configuration_snapshot(config, routes)

    Mcweb::DeveloperModeRuntime.apply!(
      config,
      settings: developer_settings(enabled: false),
      root: Rails.root,
      routes: routes,
      environment: {}
    )

    assert_equal before, configuration_snapshot(config, routes)
  end

  test "unrestricted mode applies request runtime and local integration adapters" do
    config = production_like_config
    routes = FakeRoutes.new

    Mcweb::DeveloperModeRuntime.apply!(
      config,
      settings: developer_settings(enabled: true),
      root: Rails.root,
      routes: routes,
      environment: { "MCWEB_PUBLIC_URL" => "http://192.0.2.10:3100" }
    )

    assert config.enable_reloading
    assert_not config.eager_load
    assert config.consider_all_requests_local
    assert_not config.action_controller.perform_caching
    assert_equal :null_store, config.cache_store
    assert_not config.action_controller.allow_forgery_protection
    assert_not config.assume_ssl
    assert_not config.force_ssl
    assert_empty config.ssl_options
    assert_empty config.hosts
    assert_not_includes(
      config.action_dispatch.default_headers,
      "X-Frame-Options"
    )
    assert_equal(
      "default-src 'self'",
      config.action_dispatch.default_headers["Content-Security-Policy"]
    )
    assert_includes(
      config.middleware.inserted,
      [ 0, Mcweb::DeveloperModeRuntime::AllowAllCors, [] ]
    )
    assert_equal :local, config.active_storage.service
    assert_equal :async, config.active_job.queue_adapter
    assert_equal :file, config.action_mailer.delivery_method
    assert_equal(
      Rails.root.join("tmp/developer-mode/mails"),
      config.action_mailer.file_settings.fetch(:location)
    )
    assert_equal(
      { protocol: "http", host: "192.0.2.10", port: 3100 },
      routes.default_url_options
    )
    assert_equal :debug, config.log_level
    assert config.active_record.verbose_query_logs
    assert config.active_record.query_log_tags_enabled
    assert config.active_job.verbose_enqueue_logs
    assert config.action_dispatch.verbose_redirect_logs
    assert config.server_timing
    assert config.action_view.annotate_rendered_view_with_filenames
    assert_equal(
      { "cache-control" => "no-store" },
      config.public_file_server.headers
    )
    assert config.x.mcweb.developer_mode.enabled?
  end

  test "inherit overrides preserve production values for the selected capabilities" do
    config = production_like_config
    routes = FakeRoutes.new
    settings = developer_settings(
      enabled: true,
      security: {
        csrf: "inherit",
        transport: "inherit",
        host_authorization: "inherit",
        frame_protection: "inherit",
        cors: "inherit"
      },
      integrations: {
        mail: "inherit",
        object_storage: "inherit"
      },
      runtime: {
        class_reloading: "inherit",
        eager_load: "inherit",
        full_error_reports: "inherit",
        controller_caching: "inherit",
        fragment_caching: "inherit",
        asset_cache: "inherit",
        asset_minification: "inherit",
        source_maps: "inherit",
        static_asset_far_future_headers: "inherit",
        job_backend: "inherit",
        log_level: "inherit",
        verbose_query_logs: "inherit",
        server_timing: "inherit",
        template_annotations: "inherit",
        response_compression: "inherit"
      }
    )
    before = configuration_snapshot(config, routes)

    Mcweb::DeveloperModeRuntime.apply!(
      config,
      settings: settings,
      root: Rails.root,
      routes: routes,
      environment: {}
    )

    assert_equal(
      before.except(:developer_mode),
      configuration_snapshot(config, routes).except(:developer_mode)
    )
    assert config.x.mcweb.developer_mode.enabled?
  end

  test "allow all CORS reflects arbitrary origins and terminates preflight requests" do
    calls = 0
    app = lambda do |_environment|
      calls += 1
      [ 200, { "Vary" => "Accept-Encoding" }, [ "ok" ] ]
    end
    middleware = Mcweb::DeveloperModeRuntime::AllowAllCors.new(app)

    status, headers, body = middleware.call(
      "REQUEST_METHOD" => "GET",
      "HTTP_ORIGIN" => "https://untrusted.example",
      "HTTP_ACCESS_CONTROL_REQUEST_HEADERS" => "Authorization, X-Debug"
    )

    assert_equal 200, status
    assert_equal [ "ok" ], body
    assert_equal 1, calls
    assert_equal "https://untrusted.example", headers["Access-Control-Allow-Origin"]
    assert_equal "true", headers["Access-Control-Allow-Credentials"]
    assert_equal(
      "Authorization, X-Debug",
      headers["Access-Control-Allow-Headers"]
    )
    assert_equal(
      "Accept-Encoding, Origin, Access-Control-Request-Headers, " \
        "Access-Control-Request-Private-Network",
      headers["Vary"]
    )

    status, headers, body = middleware.call(
      "REQUEST_METHOD" => "OPTIONS",
      "HTTP_ORIGIN" => "null",
      "HTTP_ACCESS_CONTROL_REQUEST_METHOD" => "DELETE",
      "HTTP_ACCESS_CONTROL_REQUEST_PRIVATE_NETWORK" => "true"
    )

    assert_equal 204, status
    assert_empty body
    assert_equal 1, calls
    assert_equal "null", headers["Access-Control-Allow-Origin"]
    assert_includes headers["Access-Control-Allow-Methods"], "DELETE"
    assert_equal "true", headers["Access-Control-Allow-Private-Network"]
    assert_equal "no-store", headers["Cache-Control"]
  end

  test "Puma worker override applies only while developer mode is enabled" do
    assert_equal 3, puma_worker_count("MCWEB_DEVELOPER_MODE" => "0")
    assert_equal 0, puma_worker_count("MCWEB_DEVELOPER_MODE" => "1")
  end

  test "Vite Ruby exports build overrides only while developer mode is enabled" do
    assert_equal({}, vite_developer_environment("MCWEB_DEVELOPER_MODE" => "0"))
    assert_equal(
      {
        "MCWEB_DEVELOPER_VITE" => "1",
        "MCWEB_DEVELOPER_VITE_MINIFICATION" => "disabled",
        "MCWEB_DEVELOPER_VITE_SOURCE_MAPS" => "enabled"
      },
      vite_developer_environment("MCWEB_DEVELOPER_MODE" => "1")
    )
  end

  test "attachment sandbox headers remain explicit developer mode boundaries" do
    %w[
      app/controllers/community/attachments_controller.rb
      app/controllers/community/uploads_controller.rb
    ].each do |relative_path|
      source = Rails.root.join(relative_path).read
      assert_includes(
        source,
        'response.headers["Content-Security-Policy"] = "sandbox"'
      )
    end
  end

  test "production requirements are granular and disabled mode requires every hardening input" do
    disabled = Mcweb::DeveloperModeRuntime.production_requirements(
      developer_settings(enabled: false)
    )
    assert disabled.values.all?

    unrestricted = Mcweb::DeveloperModeRuntime.production_requirements(
      developer_settings(enabled: true)
    )
    assert unrestricted.values.none?

    narrowed = Mcweb::DeveloperModeRuntime.production_requirements(
      developer_settings(
        enabled: true,
        security: {
          transport: "inherit",
          host_authorization: "bypass"
        },
        integrations: {
          mail: "inherit",
          object_storage: "local"
        }
      )
    )
    assert_equal(
      {
        public_origin: true,
        host_authorization: false,
        trusted_proxy_policy: true,
        mail: true,
        storage: false
      },
      narrowed
    )
  end

  test "production refuses developer mode without the exact independent confirmation" do
    environment = {
      "RAILS_ENV" => "production",
      "MCWEB_LOCAL_CONFIG_PATH" =>
        Rails.root.join("tmp/nonexistent-developer-mode.yml").to_s,
      "MCWEB_DEVELOPER_MODE" => "1",
      "MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION" => "true",
      "SECRET_KEY_BASE" => "s" * 128,
      "LOCKBOX_MASTER_KEY" => "a" * 64,
      "DATABASE_URL" =>
        "postgresql://mcweb:database-password@127.0.0.1/mcweb_production"
    }

    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      Rails.root.join("bin/rails").to_s,
      "runner",
      "puts 'PRODUCTION_DEVELOPER_MODE_STARTED'",
      chdir: Rails.root.to_s
    )

    refute status.success?
    refute_includes stdout, "PRODUCTION_DEVELOPER_MODE_STARTED"
    assert_includes(
      stdout + stderr,
      "MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION"
    )
    assert_includes stdout + stderr, "I_ACCEPT_UNSAFE_DEVELOPER_MODE"
  end

  test "production boots in developer mode without public smtp or object storage settings" do
    marker = "MCWEB_DEVELOPER_RUNTIME="
    script = <<~'RUBY'
      require "json"
      config = Rails.application.config
      payload = {
        reloading: config.enable_reloading,
        eager_load: config.eager_load,
        full_errors: config.consider_all_requests_local,
        csrf: config.action_controller.allow_forgery_protection,
        force_ssl: config.force_ssl,
        hosts: config.hosts,
        frame_header:
          config.action_dispatch.default_headers["X-Frame-Options"],
        cors_middleware: Rails.application.middleware.any? { |entry|
          entry.klass == Mcweb::DeveloperModeRuntime::AllowAllCors
        },
        storage: config.active_storage.service,
        jobs: config.active_job.queue_adapter,
        mail: config.action_mailer.delivery_method,
        log_level: config.log_level,
        server_timing: config.server_timing,
        annotations: config.action_view.annotate_rendered_view_with_filenames,
        static_headers: config.public_file_server.headers
      }
      puts "MCWEB_DEVELOPER_RUNTIME=#{JSON.generate(payload)}"
    RUBY
    environment = {
      "RAILS_ENV" => "production",
      "MCWEB_LOCAL_CONFIG_PATH" =>
        Rails.root.join("tmp/nonexistent-developer-mode.yml").to_s,
      "MCWEB_DEVELOPER_MODE" => "1",
      "MCWEB_DEVELOPER_MODE_PRODUCTION_CONFIRMATION" =>
        "I_ACCEPT_UNSAFE_DEVELOPER_MODE",
      "SECRET_KEY_BASE" => "s" * 128,
      "LOCKBOX_MASTER_KEY" => "a" * 64,
      "DATABASE_URL" =>
        "postgresql://mcweb:database-password@127.0.0.1/mcweb_production",
      "MCWEB_PUBLIC_URL" => nil,
      "MCWEB_ALLOWED_HOSTS" => nil,
      "MCWEB_SMTP_ADDRESS" => nil,
      "MCWEB_SMTP_USERNAME" => nil,
      "MCWEB_SMTP_PASSWORD" => nil,
      "MCWEB_MAIL_FROM" => nil,
      "MCWEB_S3_BUCKET" => nil,
      "MCWEB_S3_REGION" => nil,
      "MCWEB_S3_ACCESS_KEY_ID" => nil,
      "MCWEB_S3_SECRET_ACCESS_KEY" => nil,
      "RAILS_INBOUND_EMAIL_PASSWORD" => nil
    }

    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      Rails.root.join("bin/rails").to_s,
      "runner",
      script,
      chdir: Rails.root.to_s
    )

    assert status.success?, "production boot failed:\n#{stderr}\n#{stdout}"
    assert_includes(
      stdout + stderr,
      "CRITICAL: RAILS_ENV=production is running with Developer Mode"
    )
    payload_line = stdout.lines.find { |line| line.start_with?(marker) }
    assert payload_line, "runtime marker missing:\n#{stderr}\n#{stdout}"
    payload = JSON.parse(payload_line.delete_prefix(marker))

    assert_equal(
      {
        "reloading" => true,
        "eager_load" => false,
        "full_errors" => true,
        "csrf" => false,
        "force_ssl" => false,
        "hosts" => [],
        "frame_header" => nil,
        "cors_middleware" => true,
        "storage" => "local",
        "jobs" => "async",
        "mail" => "file",
        "log_level" => "debug",
        "server_timing" => true,
        "annotations" => true,
        "static_headers" => { "cache-control" => "no-store" }
      },
      payload
    )
  end

  private

  def developer_settings(
    enabled:,
    security: {},
    integrations: {},
    runtime: {}
  )
    Mcweb::DeveloperMode.parse(
      config: {
        developer_mode: {
          enabled: enabled,
          security: security,
          integrations: integrations,
          runtime: runtime
        }
      },
      environment: {}
    )
  end

  def production_like_config
    config = ActiveSupport::OrderedOptions.new
    config.x = ActiveSupport::OrderedOptions.new
    config.x.mcweb = ActiveSupport::OrderedOptions.new
    config.enable_reloading = false
    config.eager_load = true
    config.consider_all_requests_local = false
    config.cache_store = :solid_cache_store
    config.server_timing = false
    config.log_level = :info
    config.assume_ssl = true
    config.force_ssl = true
    config.ssl_options = { hsts: { expires: 31_536_000 } }
    config.hosts = [ "community.example" ]

    config.action_controller = ActiveSupport::OrderedOptions.new
    config.action_controller.perform_caching = true
    config.action_controller.allow_forgery_protection = true
    config.public_file_server = ActiveSupport::OrderedOptions.new
    config.public_file_server.enabled = true
    config.public_file_server.headers = {
      "cache-control" => "public, max-age=31536000"
    }
    config.active_storage = ActiveSupport::OrderedOptions.new
    config.active_storage.service = :private_s3
    config.active_job = ActiveSupport::OrderedOptions.new
    config.active_job.queue_adapter = :sidekiq
    config.active_job.verbose_enqueue_logs = false
    config.action_mailer = ActiveSupport::OrderedOptions.new
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.default_url_options = {
      protocol: "https",
      host: "community.example"
    }
    config.action_mailer.file_settings = nil
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.perform_caching = true
    config.active_record = ActiveSupport::OrderedOptions.new
    config.active_record.verbose_query_logs = false
    config.active_record.query_log_tags_enabled = false
    config.action_dispatch = ActiveSupport::OrderedOptions.new
    config.action_dispatch.verbose_redirect_logs = false
    config.action_dispatch.default_headers = {
      "X-Frame-Options" => "SAMEORIGIN",
      "Content-Security-Policy" => "default-src 'self'"
    }
    config.action_view = ActiveSupport::OrderedOptions.new
    config.action_view.annotate_rendered_view_with_filenames = false
    config.middleware = FakeMiddleware.new
    config
  end

  def configuration_snapshot(config, routes)
    {
      developer_mode: config.x.mcweb.developer_mode,
      reloading: config.enable_reloading,
      eager_load: config.eager_load,
      full_errors: config.consider_all_requests_local,
      cache_store: config.cache_store,
      controller_cache: config.action_controller.perform_caching,
      csrf: config.action_controller.allow_forgery_protection,
      static_enabled: config.public_file_server.enabled,
      static_headers: config.public_file_server.headers,
      storage: config.active_storage.service,
      jobs: config.active_job.queue_adapter,
      verbose_jobs: config.active_job.verbose_enqueue_logs,
      mail: config.action_mailer.delivery_method,
      mail_file_settings: config.action_mailer.file_settings,
      mail_url_options: config.action_mailer.default_url_options,
      verbose_queries: config.active_record.verbose_query_logs,
      query_tags: config.active_record.query_log_tags_enabled,
      verbose_redirects: config.action_dispatch.verbose_redirect_logs,
      default_headers: config.action_dispatch.default_headers,
      inserted_middleware: config.middleware.inserted,
      deleted_middleware: config.middleware.deleted,
      annotations: config.action_view.annotate_rendered_view_with_filenames,
      assume_ssl: config.assume_ssl,
      force_ssl: config.force_ssl,
      ssl_options: config.ssl_options,
      hosts: config.hosts,
      log_level: config.log_level,
      server_timing: config.server_timing,
      route_url_options: routes.default_url_options
    }
  end

  def puma_worker_count(overrides)
    script = <<~'RUBY'
      require "puma"
      require "puma/configuration"
      configuration = Puma::Configuration.new(
        config_files: [ "config/puma.rb" ]
      )
      configuration.clamp
      puts "MCWEB_PUMA_WORKERS=#{configuration.options[:workers]}"
    RUBY
    environment = {
      "RAILS_ENV" => "production",
      "WEB_CONCURRENCY" => "3",
      "MCWEB_LOCAL_CONFIG_PATH" =>
        Rails.root.join("tmp/nonexistent-developer-mode.yml").to_s
    }.merge(overrides)
    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      "-e",
      script,
      chdir: Rails.root.to_s
    )

    assert status.success?, "Puma config failed:\n#{stderr}\n#{stdout}"
    stdout[/MCWEB_PUMA_WORKERS=(\d+)/, 1].to_i
  end

  def vite_developer_environment(overrides)
    script = <<~'RUBY'
      require "json"
      require "vite_ruby"
      ViteRuby.config
      keys = %w[
        MCWEB_DEVELOPER_VITE
        MCWEB_DEVELOPER_VITE_MINIFICATION
        MCWEB_DEVELOPER_VITE_SOURCE_MAPS
      ]
      puts "MCWEB_VITE_ENV=#{JSON.generate(ViteRuby.env.slice(*keys))}"
    RUBY
    environment = {
      "RACK_ENV" => "production",
      "MCWEB_LOCAL_CONFIG_PATH" =>
        Rails.root.join("tmp/nonexistent-developer-mode.yml").to_s
    }.merge(overrides)
    stdout, stderr, status = Open3.capture3(
      environment,
      RbConfig.ruby,
      "-e",
      script,
      chdir: Rails.root.to_s
    )

    assert status.success?, "Vite Ruby config failed:\n#{stderr}\n#{stdout}"
    payload = stdout[/MCWEB_VITE_ENV=(\{.*\})/, 1]
    JSON.parse(payload)
  end
end
