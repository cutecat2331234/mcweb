# frozen_string_literal: true

require "yaml"
require "fileutils"
require "securerandom"
require "pathname"

module Mcweb
  module ResolveLocalConfig
    Result = Data.define(:path, :source, :created)

    module_function

    def call(
      config_path: default_config_path,
      example_path: default_example_path,
      server_root: server_root_path,
      env: default_env
    )
      return Result.new(path: config_path, source: :existing, created: false) if File.exist?(config_path)

      attrs = import_from_server_database(server_root: server_root, env: env)
      source = attrs ? :database_yml : :example

      if attrs.nil?
        FileUtils.cp(example_path, config_path)
      else
        write_config!(config_path, attrs)
      end

      Result.new(path: config_path, source: source, created: true)
    end

    def default_config_path
      Mcweb::LocalConfig.path
    end

    def default_example_path
      File.expand_path("../../config/local.yml.example", __dir__)
    end

    def server_root_path
      explicit = ENV["MCWEB_SERVER_ROOT"]
      return Pathname(explicit).expand_path if explicit && !explicit.strip.empty?

      rails_root = defined?(Rails) ? Rails.root : Pathname(File.expand_path("../..", __dir__))
      candidates = [
        rails_root.join("server"),
        rails_root.parent.join("server"),
        rails_root.join("..", "server")
      ]

      candidates.map { |path| path.expand_path }.find(&:directory?)
    end

    def default_env
      ENV.fetch("RAILS_ENV", "development")
    end

    def database_yml_candidates(server_root:)
      roots = []
      roots << Pathname(server_root).expand_path if server_root
      roots << Pathname(ENV["MCWEB_SERVER_ROOT"]).expand_path if ENV["MCWEB_SERVER_ROOT"] && !ENV["MCWEB_SERVER_ROOT"].strip.empty?

      roots.flat_map do |root|
        [
          root.join("config", "database.yml"),
          root.join("server", "config", "database.yml")
        ]
      end.uniq.select(&:file?)
    end

    def import_from_server_database(server_root:, env:)
      database_yml_candidates(server_root: server_root).each do |file|
        attrs = parse_database_yml(file, env: env)
        return attrs if attrs
      end

      nil
    end

    def parse_database_yml(path, env:)
      raw = File.read(path)
      data = YAML.safe_load(raw, permitted_classes: [ Symbol ], aliases: true)
      return nil unless data.is_a?(Hash)

      section = data[env] || data[env.to_sym]
      section ||= data["default"] || data[:default]
      return nil unless section.is_a?(Hash)

      database_name = section["database"] || section[:database]
      return nil if database_name.to_s.strip.empty?

      {
        "database" => {
          "host" => section["host"] || section[:host],
          "port" => section["port"] || section[:port],
          "username" => section["username"] || section[:username],
          "password" => section["password"] || section[:password],
          env => database_name.to_s,
          "test" => Mcweb::LocalConfig.default_database_name("test"),
          "production" => Mcweb::LocalConfig.default_database_name("production")
        },
        "secret_key_base" => SecureRandom.hex(32),
        "lockbox_master_key" => SecureRandom.hex(32),
        "redis_url" => "redis://127.0.0.1:6379/0",
        "job_concurrency" => 5
      }
    end

    def write_config!(path, attrs)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, attrs.to_yaml)
      File.chmod(0o600, path) if File.respond_to?(:chmod)
    rescue Errno::EPERM, Errno::EINVAL
      # Windows or restricted FS — ignore chmod failures
    end
  end
end
