# frozen_string_literal: true

require "rubygems"
require "yaml"
require_relative "error"

module Mcweb
  module Plugins
    module Marketplace
      class PackageMetadata
        FILE_NAME = "mcweb_package.yml"
        MAX_BYTES = 65_536
        SUPPORTED_SCHEMA_VERSIONS = %w[1].freeze
        TOP_LEVEL_KEYS = %w[schema_version plugin compatibility].freeze
        PLUGIN_KEYS = %w[id version].freeze
        COMPATIBILITY_KEYS = %w[plugin_api rails ruby].freeze

        attr_reader :schema_version, :plugin_id, :plugin_version, :requirements

        def self.load_file(path)
          yaml = File.open(path, "rb") { |file| file.read(MAX_BYTES + 1) }
          raise PackageError, "#{FILE_NAME} is too large" if yaml.bytesize > MAX_BYTES

          yaml.force_encoding(Encoding::UTF_8)
          raise PackageError, "#{FILE_NAME} must be valid UTF-8" unless yaml.valid_encoding?
          reject_duplicate_mapping_keys!(yaml)

          parsed = YAML.safe_load(
            yaml,
            permitted_classes: [],
            permitted_symbols: [],
            aliases: false
          )
          new(parsed)
        rescue Psych::Exception => e
          raise PackageError, "invalid safe YAML in #{FILE_NAME}: #{e.message}"
        end

        def self.reject_duplicate_mapping_keys!(yaml)
          visit_yaml_node(Psych.parse_stream(yaml))
        end
        private_class_method :reject_duplicate_mapping_keys!

        def self.visit_yaml_node(node)
          case node
          when Psych::Nodes::Mapping
            seen = {}
            node.children.each_slice(2) do |key, value|
              unless key.is_a?(Psych::Nodes::Scalar)
                raise PackageError, "#{FILE_NAME} mapping keys must be scalar strings"
              end
              raise PackageError, "duplicate #{FILE_NAME} key #{key.value.inspect}" if seen.key?(key.value)

              seen[key.value] = true
              visit_yaml_node(value)
            end
          when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
            node.children.each { |child| visit_yaml_node(child) }
          end
        end
        private_class_method :visit_yaml_node

        def initialize(attributes)
          data = string_keyed_mapping(attributes, "package metadata")
          reject_unknown_keys!(data, TOP_LEVEL_KEYS, "package metadata")

          @schema_version = required_string(data, "schema_version", "package metadata").freeze
          unless SUPPORTED_SCHEMA_VERSIONS.include?(schema_version)
            raise CompatibilityError, "unsupported package metadata schema #{schema_version.inspect}"
          end

          plugin = string_keyed_mapping(data["plugin"], "plugin metadata")
          reject_unknown_keys!(plugin, PLUGIN_KEYS, "plugin metadata")
          @plugin_id = required_string(plugin, "id", "plugin metadata").freeze
          @plugin_version = required_string(plugin, "version", "plugin metadata").freeze

          compatibility = string_keyed_mapping(data.fetch("compatibility", {}), "compatibility metadata")
          reject_unknown_keys!(compatibility, COMPATIBILITY_KEYS, "compatibility metadata")
          @requirements = compatibility.sort.to_h do |name, requirement|
            requirement = required_string(compatibility, name, "compatibility metadata")
            begin
              Gem::Requirement.new(requirement)
            rescue ArgumentError => e
              raise PackageError, "invalid #{name} compatibility requirement: #{e.message}"
            end
            [ name.freeze, requirement.freeze ]
          end.freeze
          freeze
        end

        def validate!(manifest:, ruby_version:, rails_version:)
          if plugin_id != manifest.id || plugin_version != manifest.version
            raise PackageError, "#{FILE_NAME} plugin identity does not match mcweb_plugin.yml"
          end

          validate_requirement!("plugin_api", manifest.api_version)
          validate_requirement!("ruby", ruby_version)
          validate_requirement!("rails", rails_version)
          true
        end

        def to_h
          {
            schema_version: schema_version,
            plugin_id: plugin_id,
            plugin_version: plugin_version,
            compatibility: requirements
          }.freeze
        end

        private

        def validate_requirement!(name, version)
          requirement = requirements[name]
          return unless requirement
          return if Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(version.to_s))

          raise CompatibilityError, "#{name} #{version} does not satisfy #{requirement}"
        end

        def string_keyed_mapping(value, label)
          raise PackageError, "#{label} must be a mapping" unless value.is_a?(Hash)

          value.each_with_object({}) do |(key, child), normalized|
            raise PackageError, "#{label} keys must be strings" unless key.is_a?(String)
            raise PackageError, "duplicate #{label} key #{key.inspect}" if normalized.key?(key)

            normalized[key] = child
          end
        end

        def reject_unknown_keys!(data, allowed, label)
          unknown = data.keys - allowed
          raise PackageError, "unknown #{label} keys: #{unknown.sort.join(', ')}" if unknown.any?
        end

        def required_string(data, key, label)
          value = data[key]
          unless value.is_a?(String) && !value.strip.empty?
            raise PackageError, "#{label} #{key} must be a non-empty string"
          end

          value.dup
        end
      end
    end
  end
end
