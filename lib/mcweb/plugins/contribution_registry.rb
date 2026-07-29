# frozen_string_literal: true

require "json"
require "pathname"
require "yaml"
require_relative "manifest_error"
require_relative "../plugin_api/v1/normalizer"

module Mcweb
  module Plugins
    class Contribution
      TYPES = %w[navigation page ui_slot translation event entity_metadata].freeze
      SURFACES = %w[public admin].freeze
      UI_SLOTS = %w[
        dashboard.cards
        list.actions
        detail.actions
        form.fields
      ].freeze
      DIRECTIONS = %w[emits listens bidirectional].freeze
      ID_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      PHRASE_PATTERN = ID_PATTERN
      LOCALE_PATTERN = /\A[a-z]{2,3}(?:-[A-Z]{2})?\z/
      MAX_ID_LENGTH = 191
      MAX_REFERENCES = 64
      MAX_PAYLOAD_BYTES = 262_144
      PRIORITY_RANGE = (-10_000..10_000)
      COMMON_KEYS = %w[type id priority before after requires conflicts payload].freeze
      PAYLOAD_KEYS = {
        "navigation" => %w[surface position label_phrase href permission icon],
        "page" => %w[surface path title_phrase description_phrase permission blocks],
        "ui_slot" => %w[slot kind title_phrase permission schema target],
        "translation" => %w[locale phrases],
        "event" => %w[name direction schema_version description_phrase],
        "entity_metadata" => %w[entity fields]
      }.freeze

      attr_reader :plugin_id, :type, :id, :priority, :before, :after,
                  :requires, :conflicts, :payload, :source

      def initialize(plugin_id:, attributes:, source:)
        @plugin_id = plugin_id.to_s.dup.freeze
        @namespace = plugin_id.tr("/-", "._").freeze
        data = normalize_mapping(attributes, label: "contribution")
        unknown = data.keys - COMMON_KEYS
        raise ManifestError, "unknown contribution keys: #{unknown.sort.join(', ')}" if unknown.any?

        @type = required_string(data, "type")
        @id = required_string(data, "id")
        @priority = normalize_priority(data.fetch("priority", 100))
        @before = normalize_references(data.fetch("before", []), label: "before")
        @after = normalize_references(data.fetch("after", []), label: "after")
        @requires = normalize_references(data.fetch("requires", []), label: "requires")
        @conflicts = normalize_references(data.fetch("conflicts", []), label: "conflicts")
        @payload = normalize_payload(data.fetch("payload", {}))
        @source = source.to_s.dup.freeze
        validate!
        freeze
      end

      def to_h
        {
          plugin_id:,
          type:,
          id:,
          priority:,
          before:,
          after:,
          requires:,
          conflicts:,
          payload:,
          source:
        }.freeze
      end

      private

      def validate!
        raise ManifestError, "unsupported contribution type #{type.inspect}" unless TYPES.include?(type)
        unless id.length <= MAX_ID_LENGTH && id.match?(ID_PATTERN) && id.start_with?("#{@namespace}.")
          raise ManifestError, "contribution id must use the #{@namespace} namespace"
        end
        duplicate_relations = (before & after) + (requires & conflicts)
        if duplicate_relations.any?
          raise ManifestError,
            "contribution #{id} declares incompatible relations: #{duplicate_relations.uniq.sort.join(', ')}"
        end

        allowed = PAYLOAD_KEYS.fetch(type)
        unknown = payload.keys - allowed
        if unknown.any?
          raise ManifestError,
            "unknown #{type} contribution payload keys: #{unknown.sort.join(', ')}"
        end
        send("validate_#{type}_payload!")
      end

      def validate_navigation_payload!
        require_payload_keys!("surface", "position", "label_phrase", "href")
        validate_surface!
        unless %w[header sidebar footer user_menu].include?(payload.fetch("position"))
          raise ManifestError, "navigation contribution position is unsupported"
        end
        validate_phrase!(payload.fetch("label_phrase"))
        href = payload.fetch("href")
        unless href.is_a?(String) && href.start_with?("/") && !href.start_with?("//") &&
            !href.include?("\\") && !href.match?(/[\u0000-\u001f]/)
          raise ManifestError, "navigation contribution href must be an internal absolute path"
        end
        validate_optional_permission!
      end

      def validate_page_payload!
        require_payload_keys!("surface", "path", "title_phrase", "blocks")
        validate_surface!
        path = payload.fetch("path")
        expected_prefix =
          if payload.fetch("surface") == "admin"
            "/admin/plugins/#{plugin_id}/"
          else
            "/plugins/#{plugin_id}/"
          end
        unless path.is_a?(String) && path.start_with?(expected_prefix) &&
            !path.include?("\\") && !path.include?("..")
          raise ManifestError, "page contribution path must remain below #{expected_prefix}"
        end
        validate_phrase!(payload.fetch("title_phrase"))
        validate_phrase!(payload["description_phrase"]) if payload["description_phrase"]
        unless payload.fetch("blocks").is_a?(Array) && payload.fetch("blocks").length <= 64
          raise ManifestError, "page contribution blocks must be an array with at most 64 entries"
        end
        validate_optional_permission!
      end

      def validate_ui_slot_payload!
        require_payload_keys!("slot", "kind", "title_phrase")
        raise ManifestError, "UI contribution slot is unsupported" unless UI_SLOTS.include?(payload.fetch("slot"))
        unless %w[card action field].include?(payload.fetch("kind"))
          raise ManifestError, "UI contribution kind is unsupported"
        end
        validate_phrase!(payload.fetch("title_phrase"))
        validate_optional_permission!
        if payload["target"]
          target = payload.fetch("target")
          unless target.is_a?(String) && target.start_with?("/") &&
              !target.start_with?("//") && !target.include?("\\") &&
              !target.include?("..") && !target.match?(/[\u0000-\u001f]/)
            raise ManifestError, "UI contribution target must be an internal absolute path"
          end
        end
        if payload.key?("schema") && !payload["schema"].is_a?(Hash)
          raise ManifestError, "UI contribution schema must be an object"
        end
      end

      def validate_translation_payload!
        require_payload_keys!("locale", "phrases")
        unless payload.fetch("locale").match?(LOCALE_PATTERN)
          raise ManifestError, "translation contribution locale is invalid"
        end
        phrases = payload.fetch("phrases")
        unless phrases.is_a?(Hash) && phrases.length <= 2_000
          raise ManifestError, "translation contribution phrases must be an object"
        end
        phrases.each do |key, value|
          unless key.start_with?("#{@namespace}.") && key.match?(PHRASE_PATTERN)
            raise ManifestError, "translation phrase #{key.inspect} must use the #{@namespace} namespace"
          end
          unless value.is_a?(String) && value.bytesize <= 10_000
            raise ManifestError, "translation phrase #{key.inspect} is invalid"
          end
        end
      end

      def validate_event_payload!
        require_payload_keys!("name", "direction", "schema_version", "description_phrase")
        name = payload.fetch("name")
        unless name.start_with?("#{@namespace}.") && name.match?(ID_PATTERN)
          raise ManifestError, "plugin event name must use the #{@namespace} namespace"
        end
        unless DIRECTIONS.include?(payload.fetch("direction"))
          raise ManifestError, "plugin event direction is unsupported"
        end
        unless payload.fetch("schema_version").to_s.match?(/\A[1-9]\d{0,8}\z/)
          raise ManifestError, "plugin event schema_version is invalid"
        end
        validate_phrase!(payload.fetch("description_phrase"))
      end

      def validate_entity_metadata_payload!
        require_payload_keys!("entity", "fields")
        unless payload.fetch("entity").match?(ID_PATTERN)
          raise ManifestError, "entity metadata target is invalid"
        end
        fields = payload.fetch("fields")
        unless fields.is_a?(Hash) && fields.length.between?(1, 64)
          raise ManifestError, "entity metadata fields must contain between 1 and 64 entries"
        end
        fields.each do |key, definition|
          unless key.start_with?("#{@namespace}.") && key.match?(ID_PATTERN)
            raise ManifestError, "entity metadata field #{key.inspect} must use the #{@namespace} namespace"
          end
          unless definition.is_a?(Hash) &&
              %w[string integer number boolean datetime].include?(definition["type"])
            raise ManifestError, "entity metadata field #{key.inspect} has an unsupported type"
          end
        end
      end

      def normalize_payload(value)
        data = normalize_mapping(value, label: "contribution payload")
        normalized = Mcweb::PluginApi::V1::Normalizer.call(data)
        if JSON.generate(normalized).bytesize > MAX_PAYLOAD_BYTES
          raise ManifestError, "contribution payload is too large"
        end
        normalized
      rescue TypeError, JSON::GeneratorError => e
        raise ManifestError, "contribution payload must be JSON-compatible: #{e.message}"
      end

      def normalize_references(value, label:)
        unless value.is_a?(Array) && value.length <= MAX_REFERENCES
          raise ManifestError, "contribution #{label} must be an array with at most #{MAX_REFERENCES} entries"
        end
        references = value.map do |entry|
          unless entry.is_a?(String) && entry.length <= MAX_ID_LENGTH && entry.match?(ID_PATTERN)
            raise ManifestError, "contribution #{label} contains an invalid contribution id"
          end
          entry.dup.freeze
        end
        raise ManifestError, "contribution #{label} contains duplicates" unless references.uniq.length == references.length

        references.sort.freeze
      end

      def normalize_priority(value)
        unless value.is_a?(Integer) && PRIORITY_RANGE.cover?(value)
          raise ManifestError, "contribution priority must be within #{PRIORITY_RANGE}"
        end
        value
      end

      def normalize_mapping(value, label:)
        raise ManifestError, "#{label} must be a mapping" unless value.is_a?(Hash)

        value.each_with_object({}) do |(raw_key, child), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "#{label} keys must be strings"
          end
          key = raw_key.to_s
          raise ManifestError, "duplicate #{label} key #{key.inspect}" if result.key?(key)

          result[key] = child
        end
      end

      def required_string(data, key)
        value = data[key]
        unless value.is_a?(String) && value.length.between?(1, MAX_ID_LENGTH)
          raise ManifestError, "contribution #{key} must be a non-empty string"
        end
        value.dup.freeze
      end

      def require_payload_keys!(*keys)
        missing = keys - payload.keys
        raise ManifestError, "#{type} contribution payload is missing: #{missing.join(', ')}" if missing.any?
      end

      def validate_surface!
        raise ManifestError, "#{type} contribution surface is unsupported" unless SURFACES.include?(payload.fetch("surface"))
      end

      def validate_phrase!(value)
        unless value.is_a?(String) && value.start_with?("#{@namespace}.") &&
            value.match?(PHRASE_PATTERN)
          raise ManifestError, "contribution phrase must use the #{@namespace} namespace"
        end
      end

      def validate_optional_permission!
        return unless payload["permission"]
        unless payload["permission"].is_a?(String) && payload["permission"].match?(ID_PATTERN)
          raise ManifestError, "contribution permission key is invalid"
        end
      end
    end

    class ContributionDocumentLoader
      MAX_FILE_BYTES = 2_097_152
      MAX_CONTRIBUTIONS = 1_000
      ROOT_KEYS = %w[schema_version contributions].freeze
      EMPTY = [].freeze

      def self.load(manifest)
        new(manifest).load
      end

      def initialize(manifest)
        @manifest = manifest
      end

      def load
        relative_path = @manifest.contribution_catalog_path
        return EMPTY unless relative_path
        raise ManifestError, "contribution catalog requires a file-backed manifest" unless @manifest.source_path

        source = resolve_source(relative_path)
        yaml = File.open(source, "rb") { |file| file.read(MAX_FILE_BYTES + 1) }
        raise ManifestError, "contribution catalog is too large" if yaml.bytesize > MAX_FILE_BYTES

        yaml.force_encoding(Encoding::UTF_8)
        raise ManifestError, "contribution catalog must be valid UTF-8" unless yaml.valid_encoding?

        yaml.delete_prefix!("\uFEFF")
        reject_duplicate_mapping_keys!(yaml)
        parsed = YAML.safe_load(yaml, permitted_classes: [], permitted_symbols: [], aliases: false)
        normalize_document(parsed, source:)
      rescue Psych::Exception => e
        raise ManifestError, "invalid safe contribution catalog YAML: #{e.message}"
      rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP => e
        raise ManifestError, "invalid contribution catalog file: #{e.message}"
      end

      private

      def normalize_document(parsed, source:)
        raise ManifestError, "contribution catalog root must be a mapping" unless parsed.is_a?(Hash)

        document = stringify_mapping(parsed, label: "contribution catalog root")
        unknown = document.keys - ROOT_KEYS
        raise ManifestError, "unknown contribution catalog keys: #{unknown.sort.join(', ')}" if unknown.any?
        unless document["schema_version"].to_s == "1"
          raise ManifestError, "unsupported contribution catalog schema_version"
        end
        entries = document["contributions"]
        unless entries.is_a?(Array) && entries.length <= MAX_CONTRIBUTIONS
          raise ManifestError, "contributions must be an array with at most #{MAX_CONTRIBUTIONS} entries"
        end
        contributions = entries.map do |attributes|
          Contribution.new(plugin_id: @manifest.id, attributes:, source: source.to_s)
        end
        duplicates = contributions.group_by(&:id).select { |_id, values| values.many? }.keys
        raise ManifestError, "duplicate contribution ids: #{duplicates.sort.join(', ')}" if duplicates.any?

        contributions.freeze
      end

      def resolve_source(relative_path)
        root = Pathname(@manifest.source_path).dirname.realpath
        candidate = root.join(relative_path).cleanpath
        raise ManifestError, "contribution catalog does not exist" unless candidate.file?

        candidate_real = candidate.realpath
        relative = candidate_real.relative_path_from(root)
        if relative.absolute? || relative.each_filename.first == ".."
          raise ManifestError, "contribution catalog must remain inside the plugin directory"
        end
        candidate_real
      rescue ArgumentError
        raise ManifestError, "contribution catalog must remain inside the plugin directory"
      end

      def stringify_mapping(value, label:)
        value.each_with_object({}) do |(raw_key, child), result|
          unless raw_key.is_a?(String) || raw_key.is_a?(Symbol)
            raise ManifestError, "#{label} keys must be strings"
          end
          key = raw_key.to_s
          raise ManifestError, "duplicate #{label} key #{key.inspect}" if result.key?(key)

          result[key] = child
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
            raise ManifestError, "contribution keys must be scalar strings" unless key.is_a?(Psych::Nodes::Scalar)

            normalized = key.value.to_s
            raise ManifestError, "duplicate contribution key #{normalized.inspect}" if seen[normalized]

            seen[normalized] = true
            visit_yaml_node(value)
          end
        when Psych::Nodes::Stream, Psych::Nodes::Document, Psych::Nodes::Sequence
          node.children.each { |child| visit_yaml_node(child) }
        end
      end
    end

    class ContributionCatalog
      Conflict = Data.define(
        :code, :plugin_id, :contribution_id, :other_plugin_id,
        :other_contribution_id, :resolved_order, :recommendation
      )

      def initialize
        @entries = {}
        @ordered_ids = []
        @mutex = Mutex.new
      end

      def activate(contributions)
        return [].freeze if contributions.empty?
        plugin_ids = contributions.map(&:plugin_id).uniq
        raise ArgumentError, "contributions must belong to one plugin" unless plugin_ids.one?

        @mutex.synchronize do
          candidate = @entries.dup
          conflicts = structural_conflicts(candidate, contributions)
          return conflicts.freeze if conflicts.any?

          contributions.each { |entry| candidate[entry.id] = entry }
          order, cycle = resolve_order(candidate)
          if cycle.any?
            return cycle.map do |id|
              entry = candidate.fetch(id)
              conflict(
                code: "ordering_cycle",
                entry:,
                other: nil,
                order:,
                recommendation: "remove or change before/after relations involving #{cycle.sort.join(', ')}"
              )
            end.freeze
          end

          @entries = candidate
          @ordered_ids = order
          [].freeze
        end
      end

      def deactivate(plugin_id)
        @mutex.synchronize do
          @entries.delete_if { |_id, entry| entry.plugin_id == plugin_id.to_s }
          @ordered_ids, = resolve_order(@entries)
        end
        true
      end

      def clear
        @mutex.synchronize do
          @entries = {}
          @ordered_ids = []
        end
        true
      end

      def all(type: nil)
        @mutex.synchronize do
          entries = @ordered_ids.filter_map { |id| @entries[id] }
          entries.select! { |entry| entry.type == type.to_s } if type
          entries.dup.freeze
        end
      end

      def for_plugin(plugin_id)
        all.select { |entry| entry.plugin_id == plugin_id.to_s }.freeze
      end

      def find(id)
        @mutex.synchronize { @entries[id.to_s] }
      end

      private

      def structural_conflicts(candidate, additions)
        additions.flat_map do |entry|
          conflicts = []
          existing = candidate[entry.id]
          if existing && existing.plugin_id != entry.plugin_id
            conflicts << conflict(
              code: "duplicate_id",
              entry:,
              other: existing,
              order: @ordered_ids,
              recommendation: "rename #{entry.id} within the #{entry.plugin_id} namespace"
            )
          end
          entry.requires.each do |required_id|
            next if candidate.key?(required_id) || additions.any? { |item| item.id == required_id }

            conflicts << conflict(
              code: "missing_required_contribution",
              entry:,
              other: nil,
              order: @ordered_ids,
              recommendation: "install or enable the plugin that provides #{required_id}"
            )
          end
          entry.conflicts.each do |conflicting_id|
            other = candidate[conflicting_id] || additions.find { |item| item.id == conflicting_id }
            next unless other

            conflicts << conflict(
              code: "explicit_conflict",
              entry:,
              other:,
              order: @ordered_ids,
              recommendation: "disable one contribution or remove the explicit conflict"
            )
          end
          candidate.each_value do |other|
            next unless other.conflicts.include?(entry.id)

            conflicts << conflict(
              code: "explicit_conflict",
              entry:,
              other:,
              order: @ordered_ids,
              recommendation: "disable one contribution or remove the explicit conflict"
            )
          end
          conflicts
        end.uniq
      end

      def resolve_order(entries)
        edges = entries.transform_values { [] }
        indegree = entries.transform_values { 0 }
        entries.each_value do |entry|
          entry.before.each { |target| add_edge(edges, indegree, entry.id, target) if entries.key?(target) }
          entry.after.each { |target| add_edge(edges, indegree, target, entry.id) if entries.key?(target) }
          entry.requires.each { |target| add_edge(edges, indegree, target, entry.id) if entries.key?(target) }
        end
        ready = entries.values.select { |entry| indegree.fetch(entry.id).zero? }
          .sort_by { |entry| sort_key(entry) }
        order = []
        until ready.empty?
          entry = ready.shift
          order << entry.id
          edges.fetch(entry.id).sort.each do |target|
            indegree[target] -= 1
            if indegree[target].zero?
              ready << entries.fetch(target)
              ready.sort_by! { |candidate| sort_key(candidate) }
            end
          end
        end
        [ order.freeze, (entries.keys - order).sort.freeze ]
      end

      def add_edge(edges, indegree, from, to)
        return if edges.fetch(from).include?(to)

        edges.fetch(from) << to
        indegree[to] += 1
      end

      def sort_key(entry)
        [ entry.priority, entry.plugin_id, entry.id ]
      end

      def conflict(code:, entry:, other:, order:, recommendation:)
        Conflict.new(
          code:,
          plugin_id: entry.plugin_id,
          contribution_id: entry.id,
          other_plugin_id: other&.plugin_id,
          other_contribution_id: other&.id,
          resolved_order: order.dup.freeze,
          recommendation: recommendation.to_s.freeze
        )
      end
    end

    # Public SDK name and Zeitwerk file contract. ContributionCatalog remains
    # as the backwards-readable implementation name used by early tests.
    ContributionRegistry = ContributionCatalog
  end
end
