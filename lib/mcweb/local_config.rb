# frozen_string_literal: true

require "yaml"
require "securerandom"

module Mcweb
  module LocalConfig
    class << self
      def path
        ENV.fetch("MCWEB_LOCAL_CONFIG_PATH") { default_path }
      end

      def default_path
        File.expand_path("../../config/local.yml", __dir__)
      end

      def exist?
        File.exist?(path)
      end

      def load
        @load ||= read_file
      end

      def load_strict
        read_file(strict: true)
      end

      def reload!
        @load = nil
        load
      end

      def [](*keys)
        load.dig(*keys.map(&:to_s))
      end

      def complete?
        db = load["database"] || {}
        db.is_a?(Hash) &&
          db.key?("password") &&
          db["password"].is_a?(String) &&
          load["secret_key_base"].present? &&
          load["lockbox_master_key"].present?
      end

      def database_settings_for(env, environment: ENV)
        db = load["database"] || {}
        if env.to_s == "production" && production_database_environment?(environment)
          return {
            "host" => normalized_optional_value(environment["MCWEB_DATABASE_HOST"]),
            "port" => normalized_optional_value(environment["MCWEB_DATABASE_PORT"]),
            "username" => normalized_optional_value(environment["MCWEB_DATABASE_USERNAME"]),
            "password" => database_password_from_environment(environment),
            "database" => environment["MCWEB_DATABASE_NAME"].to_s.strip.presence ||
              db[env] ||
              default_database_name(env)
          }.compact
        end

        settings = {
          "host" => normalized_optional_value(db["host"]),
          "port" => normalized_optional_value(db["port"]),
          "username" => normalized_optional_value(db["username"]),
          "password" => db["password"],
          "database" => db[env] || default_database_name(env)
        }
        settings.compact
      end

      def default_database_name(env)
        "mcweb_#{env}"
      end

      def normalized_database_configuration(attributes, development_database:)
        data = attributes.with_indifferent_access
        configuration = {
          "host" => normalized_optional_value(data[:host]),
          "port" => normalized_optional_value(data[:port])&.to_i,
          "username" => normalized_optional_value(data[:username]),
          "development" => development_database,
          "test" => data[:test_database].presence || default_database_name("test"),
          "production" => data[:production_database].presence || default_database_name("production")
        }.compact
        if data.key?(:password) && data[:password].is_a?(String)
          configuration["password"] = data[:password].to_s
        end
        configuration
      end

      def write!(attrs)
        data = deep_merge(load, stringify_keys(attrs))
        data["secret_key_base"] ||= SecureRandom.hex(32)
        data["lockbox_master_key"] ||= SecureRandom.hex(32)
        File.write(path, data.to_yaml)
        reload!
        data
      end

      private

      def normalized_optional_value(value)
        return value unless value.respond_to?(:strip)

        value.strip.presence
      end

      def database_password_from_environment(environment)
        value = environment["MCWEB_DATABASE_PASSWORD"]
        value if environment.key?("MCWEB_DATABASE_PASSWORD") && value.is_a?(String)
      end

      def production_database_environment?(environment)
        %w[
          MCWEB_DATABASE_HOST
          MCWEB_DATABASE_PORT
          MCWEB_DATABASE_USERNAME
          MCWEB_DATABASE_PASSWORD
          MCWEB_DATABASE_NAME
        ].any? { |key| environment.key?(key) }
      end

      def read_file(strict: false)
        return {} unless exist?

        YAML.safe_load_file(path, permitted_classes: [ Symbol ], aliases: true) || {}
      rescue Psych::SyntaxError
        raise if strict

        {}
      end

      def stringify_keys(value)
        case value
        when Hash
          value.transform_keys(&:to_s).transform_values { |entry| stringify_keys(entry) }
        else
          value
        end
      end

      def deep_merge(base, overlay)
        base.merge(overlay) do |_, left, right|
          if left.is_a?(Hash) && right.is_a?(Hash)
            deep_merge(left, right)
          else
            right
          end
        end
      end
    end
  end
end
