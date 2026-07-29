# frozen_string_literal: true

require "rubygems"
require "pathname"
require "yaml"
require_relative "manifest_canonicalizer"

module Mcweb
  module Plugins
    class Manifest
      ID_PATTERN = /\A[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\/[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*\z/
      SEMVER_PATTERN = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/
      CAPABILITY_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      MAX_MANIFEST_BYTES = 1_048_576
      MAX_ID_LENGTH = 191
      MAX_VERSION_LENGTH = 128
      MAX_ENTRYPOINT_LENGTH = 1_024
      MAX_SETUP_LENGTH = 1_024
      MAX_DEPENDENCIES = 256
      MAX_CAPABILITIES = 256
      MAX_CAPABILITY_LENGTH = 191
      MAX_CONTRIBUTION_PATH_LENGTH = 1_024
      SUPPORTED_API_VERSIONS = %w[1].freeze
      REQUIRED_KEYS = %w[id name version api_version].freeze
      OPTIONAL_STRING_KEYS = %w[description author homepage].freeze
      CONTRIBUTION_KEYS = %w[catalog jobs permissions settings].freeze
      ALLOWED_KEYS = (
        REQUIRED_KEYS + %w[
          description author homepage requires capabilities contributions
          entrypoint setup
        ]
      ).freeze

      attr_reader :id, :name, :version, :api_version, :description, :author,
                  :homepage, :requires, :capabilities, :contributions,
                  :entrypoint, :setup, :source_path

      def self.from_hash(attributes, source_path: nil)
        new(attributes, source_path:)
      end

      def self.load_file(path)
        source = Pathname(path).expand_path
        raise ManifestError, "manifest does not exist: #{source}" unless source.file?

        yaml = File.open(source, "rb") { |file| file.read(MAX_MANIFEST_BYTES + 1) }
        raise ManifestError, "manifest is too large" if yaml.bytesize > MAX_MANIFEST_BYTES

        yaml.force_encoding(Encoding::UTF_8)
        raise ManifestError, "manifest must be valid UTF-8" unless yaml.valid_encoding?
        yaml.delete_prefix!("\uFEFF")
        reject_duplicate_mapping_keys!(yaml)

        parsed = YAML.safe_load(
          yaml,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        raise ManifestError, "manifest root must be a mapping" unless parsed.is_a?(Hash)

        from_hash(parsed, source_path: source.to_s)
      rescue Psych::Exception => e
        raise ManifestError, "invalid safe YAML: #{e.message}"
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
              raise ManifestError, "manifest mapping keys must be scalar strings"
            end

            normalized_key = key.value.to_s
            if seen.key?(normalized_key)
              raise ManifestError, "duplicate manifest key #{normalized_key.inspect}"
            end
            seen[normalized_key] = true
            visit_yaml_node(value)
          end
        when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
          node.children.each { |child| visit_yaml_node(child) }
        end
      end
      private_class_method :visit_yaml_node

      def initialize(attributes, source_path: nil)
        raise ManifestError, "manifest must be a mapping" unless attributes.is_a?(Hash)

        data = attributes.each_with_object({}) do |(raw_key, value), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "manifest keys must be strings"
          end

          key = raw_key.to_s
          raise ManifestError, "duplicate manifest key #{key.inspect}" if result.key?(key)

          result[key] = value
        end
        unknown = data.keys - ALLOWED_KEYS
        raise ManifestError, "unknown manifest keys: #{unknown.sort.join(', ')}" if unknown.any?

        missing = REQUIRED_KEYS.select { |key| data[key].blank? }
        raise ManifestError, "missing manifest keys: #{missing.join(', ')}" if missing.any?
        (REQUIRED_KEYS + OPTIONAL_STRING_KEYS).each do |key|
          next if data[key].nil? || data[key].is_a?(String)

          raise ManifestError, "#{key} must be a string"
        end

        @id = immutable_string(data.fetch("id"))
        @name = immutable_string(data.fetch("name"), strip: true)
        @version = immutable_string(data.fetch("version"))
        @api_version = immutable_string(data.fetch("api_version"))
        @description = immutable_optional_string(data["description"])
        @author = immutable_optional_string(data["author"])
        @homepage = immutable_optional_string(data["homepage"])
        @requires = normalize_requires(data.fetch("requires", {}))
        @capabilities = normalize_capabilities(data.fetch("capabilities", []))
        @contributions = normalize_contributions(data.fetch("contributions", {}))
        @entrypoint = normalize_ruby_path(data["entrypoint"], key: "entrypoint", max_length: MAX_ENTRYPOINT_LENGTH)
        @setup = normalize_ruby_path(data["setup"], key: "setup", max_length: MAX_SETUP_LENGTH)
        @source_path = immutable_optional_string(source_path)
        @version_object = Gem::Version.new(version.split("+", 2).first).freeze

        validate!
        freeze
      end

      def version_object
        @version_object
      end

      def requirement_for(plugin_id)
        requirement = Gem::Requirement.new(requires.fetch(plugin_id))
        requirement.requirements.each do |operator, version|
          operator.freeze
          version.freeze
        end
        requirement.requirements.each(&:freeze)
        requirement.requirements.freeze
        requirement.freeze
      end

      def permission_contributions_path
        contributions["permissions"]
      end

      def settings_contribution_path
        contributions["settings"]
      end

      def jobs_contribution_path
        contributions["jobs"]
      end

      def contribution_catalog_path
        contributions["catalog"]
      end

      def to_h
        {
          id: id,
          name: name,
          version: version,
          api_version: api_version,
          description: description,
          author: author,
          homepage: homepage,
          requires: requires,
          capabilities: capabilities,
          contributions: contributions,
          entrypoint: entrypoint,
          setup: setup,
          source_path: source_path
        }.freeze
      end

      def canonical_hash
        ManifestCanonicalizer.new(self).canonical_hash
      end

      def canonical_json
        ManifestCanonicalizer.new(self).canonical_json
      end

      def canonical_sha256
        ManifestCanonicalizer.new(self).sha256
      end

      alias_method :canonical_digest, :canonical_sha256

      private

      def immutable_string(value, strip: false)
        string = value.to_s.dup
        string = string.strip if strip
        string.freeze
      end

      def immutable_optional_string(value)
        return nil if value.nil?

        string = immutable_string(value)
        string.strip.empty? ? nil : string
      end

      def validate!
        raise ManifestError, "id must use strict vendor/name format" unless id.match?(ID_PATTERN)
        raise ManifestError, "id is too long" if id.length > MAX_ID_LENGTH
        raise ManifestError, "name must be between 1 and 120 characters" unless name.length.between?(1, 120)
        raise ManifestError, "version must be SemVer MAJOR.MINOR.PATCH" unless version.match?(SEMVER_PATTERN)
        raise ManifestError, "version is too long" if version.length > MAX_VERSION_LENGTH
        unless SUPPORTED_API_VERSIONS.include?(api_version)
          raise ManifestError, "unsupported api_version #{api_version.inspect}; supported: #{SUPPORTED_API_VERSIONS.join(', ')}"
        end
        if requires.key?(id)
          raise ManifestError, "plugin cannot require itself"
        end
      end

      def normalize_requires(value)
        raise ManifestError, "requires must be a mapping" unless value.is_a?(Hash)
        raise ManifestError, "requires has too many entries" if value.length > MAX_DEPENDENCIES

        normalized = value.each_with_object({}) do |(plugin_id, requirement), result|
          raise ManifestError, "dependency ids must be strings" unless plugin_id.is_a?(String)

          plugin_id = immutable_string(plugin_id)
          raise ManifestError, "invalid dependency id #{plugin_id.inspect}" unless plugin_id.match?(ID_PATTERN)
          raise ManifestError, "dependency id is too long" if plugin_id.length > MAX_ID_LENGTH
          raise ManifestError, "duplicate dependency #{plugin_id}" if result.key?(plugin_id)
          raise ManifestError, "dependency requirement for #{plugin_id} must be a string" unless requirement.is_a?(String)

          requirement = immutable_string(requirement)
          begin
            Gem::Requirement.new(requirement)
          rescue ArgumentError => e
            raise ManifestError, "invalid dependency requirement for #{plugin_id}: #{e.message}"
          end
          result[plugin_id] = requirement.freeze
        end
        normalized.sort.to_h.freeze
      end

      def normalize_capabilities(value)
        raise ManifestError, "capabilities must be an array" unless value.is_a?(Array)
        raise ManifestError, "capabilities has too many entries" if value.length > MAX_CAPABILITIES

        capabilities = value.map do |capability|
          raise ManifestError, "capabilities must be strings" unless capability.is_a?(String)

          capability = immutable_string(capability)
          unless capability.match?(CAPABILITY_PATTERN)
            raise ManifestError, "invalid capability #{capability.inspect}"
          end
          raise ManifestError, "capability is too long" if capability.length > MAX_CAPABILITY_LENGTH
          capability
        end
        raise ManifestError, "capabilities must be unique" unless capabilities.uniq.length == capabilities.length

        capabilities.sort.freeze
      end

      def normalize_contributions(value)
        raise ManifestError, "contributions must be a mapping" unless value.is_a?(Hash)

        normalized = value.each_with_object({}) do |(raw_key, path), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "contribution keys must be strings"
          end

          key = immutable_string(raw_key.to_s)
          raise ManifestError, "duplicate contribution #{key.inspect}" if result.key?(key)
          unless CONTRIBUTION_KEYS.include?(key)
            raise ManifestError, "unknown contribution keys: #{key}"
          end

          result[key] = normalize_contribution_path(path, key:)
        end
        normalized.sort.to_h.freeze
      end

      def normalize_contribution_path(value, key:)
        unless value.is_a?(String) && value.length.between?(1, MAX_CONTRIBUTION_PATH_LENGTH)
          raise ManifestError,
            "contributions.#{key} must be a relative YAML path up to #{MAX_CONTRIBUTION_PATH_LENGTH} characters"
        end
        if value.include?("\\")
          raise ManifestError, "contributions.#{key} must use forward slashes"
        end

        path = Pathname(value).cleanpath
        if path.absolute? || path.each_filename.any? { |part| part == ".." }
          raise ManifestError, "contributions.#{key} must remain inside the plugin directory"
        end
        unless %w[.yml .yaml].include?(path.extname.downcase)
          raise ManifestError, "contributions.#{key} must name a YAML file"
        end

        immutable_string(path.to_s)
      rescue ArgumentError => e
        raise ManifestError, "invalid contributions.#{key}: #{e.message}"
      end

      def normalize_ruby_path(value, key:, max_length:)
        return nil if value.blank?
        raise ManifestError, "#{key} must be a string" unless value.is_a?(String)
        raise ManifestError, "#{key} is too long" if value.length > max_length

        path = Pathname(value)
        if path.absolute? || path.each_filename.any? { |part| part == ".." }
          raise ManifestError, "#{key} must remain inside the plugin directory"
        end
        raise ManifestError, "#{key} must name a Ruby file" unless path.extname == ".rb"

        immutable_string(value)
      rescue ArgumentError => e
        raise ManifestError, "invalid #{key}: #{e.message}"
      end
    end
  end
end
