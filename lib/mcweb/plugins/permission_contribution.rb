# frozen_string_literal: true

require "pathname"
require "yaml"

module Mcweb
  module Plugins
    class PermissionContribution
      SCOPES = %w[global].freeze
      DEFAULT_RECOMMENDATIONS = %w[none member staff admin].freeze
      MAX_KEY_LENGTH = 191
      PHRASE_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/

      attr_reader :plugin_id, :id, :group, :title_phrase,
                  :description_phrase, :scope, :default

      def initialize(plugin_id:, attributes:)
        @plugin_id = immutable_string(plugin_id)
        data = normalize_attributes(attributes)
        @id = required_string(data, "id")
        @group = required_string(data, "group")
        @title_phrase = required_string(data, "title_phrase")
        @description_phrase = required_string(data, "description_phrase")
        @scope = required_string(data, "scope")
        @default = required_string(data, "default")
        validate!
        freeze
      end

      def to_h
        {
          plugin_id: plugin_id,
          id: id,
          group: group,
          title_phrase: title_phrase,
          description_phrase: description_phrase,
          scope: scope,
          default: default
        }.freeze
      end

      private

      def normalize_attributes(attributes)
        raise ManifestError, "permission contribution must be a mapping" unless attributes.is_a?(Hash)

        data = attributes.each_with_object({}) do |(raw_key, value), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "permission contribution keys must be strings"
          end

          key = raw_key.to_s
          raise ManifestError, "duplicate permission contribution key #{key.inspect}" if result.key?(key)

          result[key] = value
        end
        allowed = %w[id group title_phrase description_phrase scope default]
        unknown = data.keys - allowed
        if unknown.any?
          raise ManifestError,
            "unknown permission contribution keys: #{unknown.sort.join(', ')}"
        end
        missing = allowed.select { |key| !data.key?(key) }
        if missing.any?
          raise ManifestError,
            "missing permission contribution keys: #{missing.join(', ')}"
        end

        data
      end

      def required_string(data, key)
        value = data.fetch(key)
        unless value.is_a?(String) && value.length.between?(1, MAX_KEY_LENGTH)
          raise ManifestError,
            "permission contribution #{key} must be a string between 1 and #{MAX_KEY_LENGTH} characters"
        end

        immutable_string(value)
      end

      def validate!
        namespace = plugin_id.tr("/-", "._")
        if id.start_with?("mcweb.")
          raise ManifestError, "permission contribution id cannot use the reserved mcweb namespace"
        end

        segment = "[a-z][a-z0-9_]*"
        id_pattern = /\A#{Regexp.escape(namespace)}\.#{segment}(?:\.#{segment})+\z/
        group_pattern = /\A#{Regexp.escape(namespace)}\.#{segment}(?:\.#{segment})*\z/
        unless id.match?(id_pattern)
          raise ManifestError,
            "permission contribution id must use #{namespace}.<resource>.<action>"
        end
        unless group.match?(group_pattern)
          raise ManifestError,
            "permission contribution group must remain in the #{namespace} namespace"
        end
        unless title_phrase.match?(PHRASE_PATTERN)
          raise ManifestError, "permission contribution title_phrase is invalid"
        end
        unless description_phrase.match?(PHRASE_PATTERN)
          raise ManifestError, "permission contribution description_phrase is invalid"
        end
        unless SCOPES.include?(scope)
          raise ManifestError,
            "unsupported permission contribution scope #{scope.inspect}; supported: #{SCOPES.join(', ')}"
        end
        unless DEFAULT_RECOMMENDATIONS.include?(default)
          raise ManifestError,
            "unsupported permission contribution default #{default.inspect}; " \
            "supported: #{DEFAULT_RECOMMENDATIONS.join(', ')}"
        end
      end

      def immutable_string(value)
        value
          .dup
          .encode(Encoding::UTF_8)
          .unicode_normalize(:nfc)
          .gsub(/\r\n?/, "\n")
          .freeze
      end
    end

    class PermissionContributionLoader
      MAX_FILE_BYTES = 1_048_576
      MAX_PERMISSIONS = 256
      ROOT_KEYS = %w[permissions].freeze
      EMPTY = [].freeze

      def self.load(manifest)
        new(manifest).load
      end

      def initialize(manifest)
        @manifest = manifest
      end

      def load
        relative_path = @manifest.permission_contributions_path
        return EMPTY unless relative_path
        unless @manifest.source_path
          raise ManifestError,
            "permissions contribution requires a file-backed manifest"
        end

        source = resolve_source(relative_path)
        yaml = read_yaml(source)
        parsed = YAML.safe_load(
          yaml,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        normalize_document(parsed)
      rescue Psych::Exception => e
        raise ManifestError, "invalid safe permission contribution YAML: #{e.message}"
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
        raise ManifestError, "invalid permissions contribution file: #{e.message}"
      end

      private

      def resolve_source(relative_path)
        root = Pathname(@manifest.source_path).dirname.realpath
        candidate = root.join(relative_path).cleanpath
        unless candidate.file?
          raise ManifestError, "permissions contribution does not exist: #{candidate}"
        end

        candidate_real = candidate.realpath
        unless contained_path?(candidate_real, root)
          raise ManifestError,
            "permissions contribution must remain inside the plugin directory"
        end
        candidate_real
      end

      def read_yaml(source)
        yaml = File.open(source, "rb") { |file| file.read(MAX_FILE_BYTES + 1) }
        if yaml.bytesize > MAX_FILE_BYTES
          raise ManifestError, "permissions contribution is too large"
        end

        yaml.force_encoding(Encoding::UTF_8)
        unless yaml.valid_encoding?
          raise ManifestError, "permissions contribution must be valid UTF-8"
        end

        yaml.delete_prefix!("\uFEFF")
        reject_duplicate_mapping_keys!(yaml)
        yaml
      end

      def normalize_document(parsed)
        unless parsed.is_a?(Hash)
          raise ManifestError, "permissions contribution root must be a mapping"
        end

        document = normalize_mapping(parsed, label: "permissions contribution root")
        unknown = document.keys - ROOT_KEYS
        if unknown.any?
          raise ManifestError,
            "unknown permissions contribution root keys: #{unknown.sort.join(', ')}"
        end
        unless document.key?("permissions")
          raise ManifestError, "permissions contribution root must contain permissions"
        end

        entries = document.fetch("permissions")
        unless entries.is_a?(Array)
          raise ManifestError, "permissions must be an array"
        end
        if entries.length > MAX_PERMISSIONS
          raise ManifestError,
            "permissions contribution has more than #{MAX_PERMISSIONS} entries"
        end

        contributions = entries.map do |attributes|
          PermissionContribution.new(plugin_id: @manifest.id, attributes:)
        end
        duplicates = contributions.group_by(&:id).select { |_id, values| values.many? }.keys
        if duplicates.any?
          raise ManifestError,
            "duplicate permission contribution ids: #{duplicates.sort.join(', ')}"
        end

        contributions.freeze
      end

      def normalize_mapping(mapping, label:)
        mapping.each_with_object({}) do |(raw_key, value), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "#{label} keys must be strings"
          end

          key = raw_key.to_s
          raise ManifestError, "duplicate #{label} key #{key.inspect}" if result.key?(key)

          result[key] = value
        end
      end

      def reject_duplicate_mapping_keys!(yaml)
        visit_yaml_node(Psych.parse_stream(yaml))
      end

      def visit_yaml_node(node)
        case node
        when Psych::Nodes::Mapping
          seen = {}
          node.children.each_slice(2) do |key, value|
            unless key.is_a?(Psych::Nodes::Scalar)
              raise ManifestError,
                "permission contribution mapping keys must be scalar strings"
            end

            normalized_key = key.value.to_s
            if seen.key?(normalized_key)
              raise ManifestError,
                "duplicate permission contribution key #{normalized_key.inspect}"
            end
            seen[normalized_key] = true
            visit_yaml_node(value)
          end
        when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
          node.children.each { |child| visit_yaml_node(child) }
        end
      end

      def contained_path?(candidate, root)
        relative = candidate.relative_path_from(root)
        !relative.absolute? && relative.each_filename.first != ".."
      rescue ArgumentError
        false
      end
    end
  end
end
