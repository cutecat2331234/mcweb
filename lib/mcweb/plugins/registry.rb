# frozen_string_literal: true

require_relative "manifest_error"
require_relative "duplicate_plugin_error"
require_relative "lifecycle_error"
require_relative "manifest"
require_relative "definition"
require_relative "../plugin_api/v1/normalizer"
require_relative "../plugin_api/v1/event"
require "monitor"
require "pathname"
require "set"
require "time"

module Mcweb
  module Plugins
    REGISTRY_MUTEX = Mutex.new
    LIFECYCLE_MONITOR = Monitor.new

    class Registry
      EVENT_CAPABILITY = "forum.events.read"
      FILTER_CAPABILITY_SUFFIX = ".extend"
      MAX_DIAGNOSTICS = 1_000
      MAX_DIAGNOSTIC_MESSAGE_LENGTH = 4_096

      attr_reader :event_bus

      def initialize(event_bus: Mcweb::Events, logger: nil)
        @event_bus = event_bus
        @logger = logger
        @definitions = {}
        @subscriptions = {}
        @diagnostics = []
        @mutex = Mutex.new
        @lifecycle_monitor = Monitor.new
        @pending_ids = Set.new
      end

      def register(manifest = nil, **attributes)
        @lifecycle_monitor.synchronize do
          manifest = resolve_manifest(manifest, attributes)
          definition = Definition.new(
            manifest,
            event_bus:,
            capability_auditor: ->(capability) { audit_capability_use(manifest, capability) }
          )

          @mutex.synchronize do
            if @definitions.key?(manifest.id) || @pending_ids.include?(manifest.id)
              raise DuplicatePluginError, "plugin #{manifest.id} is already registered"
            end
            @pending_ids << manifest.id
          end

          begin
            yield definition if block_given?
            definition.seal!

            @mutex.synchronize do
              raise DuplicatePluginError, "plugin #{manifest.id} is already registered" if @definitions.key?(manifest.id)

              @definitions[manifest.id] = definition
            end
          ensure
            @mutex.synchronize { @pending_ids.delete(manifest.id) }
          end
          definition
        end
      end

      def boot!
        @lifecycle_monitor.synchronize do
          unsubscribe_all!
          clear_diagnostics!("activation")

          definitions = definition_snapshot
          definitions.each(&:mark_registered!)

          if Mcweb::Plugins.disabled?
            definitions.each { |definition| definition.mark_disabled!("plugins disabled by MCWEB_DISABLE_PLUGINS=1") }
            record_diagnostic(
              level: :warning, code: :plugins_disabled, phase: :activation,
              message: "plugins disabled by MCWEB_DISABLE_PLUGINS=1"
            )
            next list
          end

          order, cycle_ids = dependency_order(definitions)
          cycle_ids.each do |id|
            definition = definition_for(id)
            definition&.mark_disabled!("dependency cycle")
            record_diagnostic(
              level: :error, code: :dependency_cycle, phase: :activation,
              plugin_id: id, message: "dependency cycle includes #{id}"
            )
          end

          activation_index = 0
          order.each do |definition|
            next if cycle_ids.include?(definition.id)
            next unless dependencies_available?(definition)

            definition.mark_active!(order: activation_index)
            activation_index += 1
            audit_listener_capabilities(definition)
            audit_filter_capabilities(definition)
          end

          subscribe_to_active_events!
          list
        end
      end

      def reset!
        @lifecycle_monitor.synchronize do
          unsubscribe_all!
          @mutex.synchronize do
            @definitions.clear
            @diagnostics.clear
            @audited_capability_uses = nil
            @pending_ids.clear
          end
          true
        end
      end

      # Used by Loader to roll back every definition registered by an entrypoint
      # that subsequently failed. A stale central subscription is harmless because
      # dispatch resolves definitions afresh; the next boot/reset removes it.
      def unregister(id)
        id = id.to_s
        @lifecycle_monitor.synchronize do
          @mutex.synchronize { @definitions.delete(id) }
        end
      end

      def list
        definition_snapshot.sort_by(&:id).map(&:to_h).freeze
      end

      def ids
        @mutex.synchronize { @definitions.keys.sort.freeze }
      end

      def diagnostics
        @mutex.synchronize { @diagnostics.map(&:dup).map(&:freeze).freeze }
      end

      # Applies a deterministic, synchronous plugin filter chain. Values and
      # contexts cross the SDK boundary as immutable JSON-like data. A callback
      # that raises or changes the root value type is diagnosed and skipped so
      # one extension cannot take the host request down.
      def apply_filter(name, value, context: {})
        name = normalize_filter_name(name)
        current = Mcweb::PluginApi::V1::Normalizer.call(value)
        immutable_context = Mcweb::PluginApi::V1::Normalizer.call(context)
        filter_stack = Thread.current.thread_variable_get(filter_stack_key) || []

        if filter_stack.include?(name)
          record_diagnostic(
            level: :error,
            code: :filter_recursion,
            phase: :filter,
            event: name,
            message: "recursive filter invocation was skipped"
          )
          return current
        end

        Thread.current.thread_variable_set(filter_stack_key, filter_stack + [ name ])
        filters_for(name).each do |filter|
          begin
            candidate = Mcweb::PluginApi::V1::Normalizer.call(
              filter.callback.call(current, immutable_context)
            )
            unless compatible_filter_value?(current, candidate)
              record_diagnostic(
                level: :error,
                code: :invalid_filter_result,
                phase: :filter,
                plugin_id: filter.plugin_id,
                event: name,
                message: "filter changed the root value type from #{filter_value_type(current)} to #{filter_value_type(candidate)}"
              )
              next
            end
            current = candidate
          rescue StandardError, SystemStackError => e
            definition = definition_for(filter.plugin_id)
            definition&.record_filter_failure!(e)
            record_diagnostic(
              level: :error,
              code: :filter_error,
              phase: :filter,
              plugin_id: filter.plugin_id,
              event: name,
              message: e.message,
              exception: e
            )
            logger&.error("[mcweb.plugins] #{filter.plugin_id} filter #{name} failed: #{e.class}: #{e.message}")
          end
        end
        current
      ensure
        Thread.current.thread_variable_set(filter_stack_key, filter_stack) if defined?(filter_stack)
      end

      def record_diagnostic(level:, code:, message:, phase:, plugin_id: nil, event: nil, exception: nil)
        diagnostic = {
          level: level.to_s,
          code: code.to_s,
          phase: phase.to_s,
          plugin_id: plugin_id&.to_s,
          event: event&.to_s,
          message: normalize_diagnostic_message(message),
          exception: exception&.class&.name,
          occurred_at: Time.current.utc.iso8601(6)
        }.compact.transform_values { |value| value.is_a?(String) ? value.dup.freeze : value }.freeze
        @mutex.synchronize do
          @diagnostics << diagnostic
          excess = @diagnostics.length - MAX_DIAGNOSTICS
          @diagnostics.shift(excess) if excess.positive?
        end
        diagnostic
      end

      def with_loading_manifest(manifest)
        previous = Thread.current.thread_variable_get(loading_manifest_key)
        Thread.current.thread_variable_set(loading_manifest_key, manifest)
        yield
      ensure
        Thread.current.thread_variable_set(loading_manifest_key, previous)
      end

      private

      def normalize_diagnostic_message(message)
        message
          .to_s
          .encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "�")
          .slice(0, MAX_DIAGNOSTIC_MESSAGE_LENGTH)
      rescue StandardError
        "diagnostic message unavailable"
      end

      def resolve_manifest(manifest, attributes)
        loading_manifest = Thread.current.thread_variable_get(loading_manifest_key)
        if loading_manifest
          unless manifest.nil? && attributes.empty?
            raise ManifestError, "a discovered plugin entrypoint must call Mcweb::Plugins.register without manifest arguments"
          end
          return loading_manifest
        end

        data =
          if manifest.is_a?(Manifest)
            raise ManifestError, "cannot combine a Manifest with keyword attributes" if attributes.any?
            return manifest
          elsif manifest.is_a?(Hash)
            manifest.merge(attributes)
          elsif manifest.nil?
            attributes
          else
            raise ManifestError, "register expects a manifest mapping or keyword attributes"
          end
        Manifest.from_hash(data)
      end

      def loading_manifest_key
        @loading_manifest_key ||= :"mcweb_plugins_manifest_#{object_id}"
      end

      def definition_snapshot
        @mutex.synchronize { @definitions.values.dup }
      end

      def definition_for(id)
        @mutex.synchronize { @definitions[id] }
      end

      def clear_diagnostics!(phase)
        @mutex.synchronize { @diagnostics.reject! { |entry| entry[:phase] == phase } }
      end

      def dependency_order(definitions)
        by_id = definitions.index_by(&:id)
        state = {}
        order = []
        cycles = Set.new

        visit = lambda do |definition, stack|
          case state[definition.id]
          when :done then return
          when :visiting
            start = stack.index(definition.id) || 0
            stack[start..].each { |id| cycles << id }
            return
          end

          state[definition.id] = :visiting
          definition.manifest.requires.keys.sort.each do |dependency_id|
            dependency = by_id[dependency_id]
            visit.call(dependency, stack + [ definition.id ]) if dependency
          end
          state[definition.id] = :done
          order << definition
        end

        definitions.sort_by(&:id).each { |definition| visit.call(definition, []) }
        [ order.uniq, cycles ]
      end

      def dependencies_available?(definition)
        definition.manifest.requires.each do |dependency_id, requirement_string|
          dependency = definition_for(dependency_id)
          unless dependency
            return disable_dependency!(
              definition, :missing_dependency,
              "missing dependency #{dependency_id} (#{requirement_string})"
            )
          end

          requirement = Gem::Requirement.new(requirement_string)
          unless requirement.satisfied_by?(dependency.manifest.version_object)
            return disable_dependency!(
              definition, :dependency_version_mismatch,
              "dependency #{dependency_id} #{dependency.manifest.version} does not satisfy #{requirement_string}"
            )
          end

          unless dependency.dispatchable? || dependency.status == :active
            return disable_dependency!(
              definition, :dependency_unavailable,
              "dependency #{dependency_id} is #{dependency.status}"
            )
          end
        end
        true
      end

      def disable_dependency!(definition, code, message)
        definition.mark_disabled!(message)
        record_diagnostic(
          level: :error, code:, phase: :activation,
          plugin_id: definition.id, message:
        )
        false
      end

      def audit_listener_capabilities(definition)
        return if definition.listeners.empty? || definition.declares_capability?(EVENT_CAPABILITY)

        record_diagnostic(
          level: :warning,
          code: :undeclared_capability,
          phase: :activation,
          plugin_id: definition.id,
          message: "event listeners are registered without declaring #{EVENT_CAPABILITY}; allowed because plugins are fully trusted"
        )
      end

      def audit_filter_capabilities(definition)
        definition.filters
          .map(&:name)
          .map { |name| "#{name.split('.', 2).first}#{FILTER_CAPABILITY_SUFFIX}" }
          .uniq
          .sort
          .each do |capability|
            next if definition.declares_capability?(capability)

            record_diagnostic(
              level: :warning,
              code: :undeclared_capability,
              phase: :activation,
              plugin_id: definition.id,
              message: "filters are registered without declaring #{capability}; allowed because plugins are fully trusted"
            )
          end
      end

      def audit_capability_use(manifest, capability)
        return if manifest.capabilities.include?(capability)

        audit_key = [ manifest.id, capability ]
        first_use = @mutex.synchronize do
          @audited_capability_uses ||= Set.new
          @audited_capability_uses.add?(audit_key)
        end
        return unless first_use

        record_diagnostic(
          level: :warning,
          code: :undeclared_capability,
          phase: :runtime,
          plugin_id: manifest.id,
          message: "#{capability} used without a declaration; allowed because plugins are fully trusted"
        )
      end

      def subscribe_to_active_events!
        events = definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:listeners)
          .map(&:event)
          .uniq
          .sort

        events.each do |event|
          handle = event_bus.subscribe(event) { |payload| dispatch(event, payload) }
          @mutex.synchronize { @subscriptions[event] = handle }
        rescue StandardError => e
          record_diagnostic(
            level: :error, code: :event_subscription_failed, phase: :activation,
            event:, message: e.message, exception: e
          )
        end
      end

      def dispatch(event, payload)
        listeners = definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:listeners)
          .select { |listener| listener.event == event }
          .sort_by { |listener| [ listener.priority, listener.plugin_id, listener.sequence ] }
        begin
          dto = Mcweb::PluginApi::V1::Event.build(name: event, payload:)
        rescue StandardError, SystemStackError => e
          record_diagnostic(
            level: :error, code: :event_normalization_failed, phase: :dispatch,
            event:, message: e.message, exception: e
          )
          logger&.error("[mcweb.plugins] event #{event} could not be normalized: #{e.class}: #{e.message}")
          return false
        end

        listeners.each do |listener|
          listener.callback.call(dto)
        rescue StandardError => e
          definition = definition_for(listener.plugin_id)
          definition&.record_listener_failure!(e)
          record_diagnostic(
            level: :error, code: :listener_error, phase: :dispatch,
            plugin_id: listener.plugin_id, event:,
            message: e.message, exception: e
          )
          logger&.error("[mcweb.plugins] #{listener.plugin_id} listener for #{event} failed: #{e.class}: #{e.message}")
        end
        true
      end

      def normalize_filter_name(name)
        normalized = name.to_s
        unless normalized.length <= Definition::MAX_EVENT_NAME_LENGTH &&
            normalized.match?(Definition::EVENT_PATTERN)
          raise ArgumentError, "invalid filter name #{normalized.inspect}"
        end
        normalized
      end

      def filters_for(name)
        definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:filters)
          .select { |filter| filter.name == name }
          .sort_by { |filter| [ filter.priority, filter.plugin_id, filter.sequence ] }
      end

      def compatible_filter_value?(current, candidate)
        filter_value_type(current) == filter_value_type(candidate)
      end

      def filter_value_type(value)
        case value
        when Hash then :hash
        when Array then :array
        when String then :string
        when Numeric then :number
        when TrueClass, FalseClass then :boolean
        when NilClass then :null
        else value.class.name
        end
      end

      def filter_stack_key
        @filter_stack_key ||= :"mcweb_plugin_filter_stack_#{object_id}"
      end

      def unsubscribe_all!
        handles = @mutex.synchronize do
          current = @subscriptions.values
          @subscriptions = {}
          current
        end
        handles.each do |handle|
          event_bus.unsubscribe(handle)
        rescue StandardError => e
          logger&.warn("[mcweb.plugins] failed to unsubscribe listener: #{e.class}: #{e.message}")
        end
      end

      def logger
        @logger || (Rails.logger if defined?(Rails) && Rails.respond_to?(:logger))
      end
    end

    class << self
      def register(manifest = nil, **attributes, &block)
        LIFECYCLE_MONITOR.synchronize do
          registry.register(manifest, **attributes, &block)
        end
      end

      def registry
        return @registry if @registry

        REGISTRY_MUTEX.synchronize { @registry ||= Registry.new }
      end

      def list
        registry.list
      end

      def diagnostics
        registry.diagnostics
      end

      def apply_filter(name, value, context: {})
        registry.apply_filter(name, value, context:)
      end

      def boot!
        LIFECYCLE_MONITOR.synchronize { registry.boot! }
      end

      def reset!
        LIFECYCLE_MONITOR.synchronize { registry.reset! }
      end

      def reload!(root: default_root)
        LIFECYCLE_MONITOR.synchronize do
          registry.reset!
          if disabled?
            registry.boot!
            next list
          end

          Loader.new(root:, registry:).load!
          registry.boot!
        end
      end

      def disabled?
        ENV["MCWEB_DISABLE_PLUGINS"].to_s == "1"
      end

      def default_root
        Pathname(ENV.fetch("MCWEB_PLUGIN_DIR", Rails.root.join("plugins").to_s))
      end

      def with_loading_manifest(manifest, &block)
        registry.with_loading_manifest(manifest, &block)
      end
    end
  end
end
