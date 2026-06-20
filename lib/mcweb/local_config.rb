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

      def reload!
        @load = nil
        load
      end

      def [](*keys)
        load.dig(*keys.map(&:to_s))
      end

      def complete?
        db = load["database"] || {}
        %w[host port username password].all? { |key| db[key].present? } &&
          load["secret_key_base"].present? &&
          load["lockbox_master_key"].present?
      end

      def database_settings_for(env)
        db = load["database"] || {}
        settings = {
          "host" => db["host"],
          "port" => db["port"],
          "username" => db["username"],
          "password" => db["password"],
          "database" => db[env] || default_database_name(env)
        }
        settings.compact
      end

      def default_database_name(env)
        "mcweb_#{env}"
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

      def read_file
        return {} unless exist?

        YAML.safe_load_file(path, permitted_classes: [ Symbol ], aliases: true) || {}
      rescue Psych::SyntaxError
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
