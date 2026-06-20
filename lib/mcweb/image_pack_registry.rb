# frozen_string_literal: true

require "fileutils"
require "pathname"
require "yaml"

module Mcweb
  class ImagePackRegistry
    class << self
      def config_path
        Pathname(ENV.fetch("MCWEB_IMAGE_PACKS_PATH") { default_config_path })
      end

      def example_path
        Pathname(ENV.fetch("MCWEB_IMAGE_PACKS_EXAMPLE_PATH") { default_example_path })
      end

      def ensure_config!
        return config_path if config_path.file?

        return nil unless example_path.file?

        FileUtils.mkdir_p(config_path.dirname)
        FileUtils.cp(example_path, config_path)
        reload!
        config_path
      rescue StandardError => e
        Rails.logger.warn("[ImagePackRegistry] ensure_config! failed: #{e.message}") if defined?(Rails.logger)
        nil
      end

      def packs
        load.fetch("packs", {})
      end

      def find(pack_id)
        entry = packs[pack_id.to_s]
        return nil unless entry.is_a?(Hash)

        entry.merge("id" => pack_id.to_s)
      end

      def texture_path(pack_id, *segments)
        pack = find(pack_id)
        return nil unless pack

        root = pack["root"].presence
        return nil if root.blank?

        relative = Array(segments).flatten.compact.map(&:to_s).join("/")
        return nil if relative.blank?

        file = Pathname(root).join(relative)
        file = file.sub_ext(".png") if file.extname.empty?
        return file.to_s if file.file?

        nil
      end

      def frontend_hash
        packs.transform_values do |entry|
          next unless entry.is_a?(Hash)

          {
            "label" => entry["label"],
            "namespace" => entry["namespace"],
            "available" => entry["root"].present? && Pathname(entry["root"]).directory?
          }
        end.compact
      end

      def reload!
        @load = nil
        load
      end

      def load
        @load ||= read_config
      end

      private

      def default_config_path
        root = defined?(Rails) ? Rails.root : Pathname(File.expand_path("../..", __dir__))
        root.join("config/image_packs.yml")
      end

      def default_example_path
        root = defined?(Rails) ? Rails.root : Pathname(File.expand_path("../..", __dir__))
        root.join("config/image_packs.yml.example")
      end

      def read_config
        path = config_path
        return {} unless path.file?

        YAML.safe_load_file(path, permitted_classes: [ Symbol ], aliases: true) || {}
      rescue Psych::SyntaxError, Errno::ENOENT
        {}
      end
    end
  end
end
