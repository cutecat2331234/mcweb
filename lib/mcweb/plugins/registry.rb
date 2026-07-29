# frozen_string_literal: true

require_relative "manifest_error"
require_relative "duplicate_plugin_error"
require_relative "lifecycle_error"
require_relative "fulfillment_provider_error"
require_relative "manifest"
require_relative "permission_contribution"
require_relative "permission_contribution_catalog"
require_relative "contribution_registry"
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

    class ServiceContinuation
      def initialize(default_input:, normalizer:, input_validator:, &operation)
        @default_input = default_input
        @normalizer = normalizer
        @input_validator = input_validator
        @operation = operation
        @monitor = Monitor.new
        @condition = @monitor.new_cond
        @calls = 0
        @state = :idle
        @owner = nil
        @called = false
        @value = nil
        @error = nil
      end

      def call(input = @default_input)
        normalized_input = nil
        @monitor.synchronize do
          @calls += 1
          loop do
            case @state
            when :complete
              return result_without_lock
            when :running
              raise LifecycleError, "service continuation cannot be re-entered" if @owner == Thread.current

              @condition.wait
            else
              normalized_input = @normalizer.call(input)
              @input_validator.call(normalized_input)
              @state = :running
              @called = true
              @owner = Thread.current
              break
            end
          end
        end

        value = nil
        error = nil
        begin
          value = @operation.call(normalized_input)
        # Continuation waiters must observe the exact same terminal outcome,
        # including non-StandardError exceptions that the registry itself does
        # not isolate.
        rescue Exception => e # rubocop:disable Lint/RescueException
          error = e
        ensure
          @monitor.synchronize do
            @value = value
            @error = error
            @state = :complete
            @owner = nil
            @condition.broadcast
          end
        end
        raise error if error

        value
      end

      def calls
        @monitor.synchronize { @calls }
      end

      def called?
        @monitor.synchronize { @called }
      end

      def failed_with?(error)
        @monitor.synchronize { @called && @error.equal?(error) }
      end

      def result
        @monitor.synchronize do
          if @state == :running && @owner == Thread.current
            raise LifecycleError, "service continuation result is unavailable while it is running"
          end

          @condition.wait_while { @state == :running }
          result_without_lock
        end
      end

      private

      def result_without_lock
        raise @error if @error

        @value
      end
    end

    class Registry
      FILTER_CAPABILITY_SUFFIX = ".extend"
      FULFILLMENT_PROVIDER_CAPABILITY = "commerce.fulfillments.write"
      FULFILLMENT_PROVIDER_ID_PATTERN =
        /\A[a-z][a-z0-9_.-]*\/[a-z][a-z0-9_.-]*:[a-z][a-z0-9_.-]{0,63}\z/
      FULFILLMENT_RESULT_STATUSES = %w[succeeded retryable failed].freeze
      MAX_DIAGNOSTICS = 1_000
      MAX_DIAGNOSTIC_MESSAGE_LENGTH = 4_096

      attr_reader :event_bus

      def initialize(event_bus: Mcweb::Events, logger: nil)
        @event_bus = event_bus
        @logger = logger
        @definitions = {}
        @subscriptions = {}
        @diagnostics = []
        @permission_catalog = PermissionContributionCatalog.new
        @contribution_catalog = ContributionRegistry.new
        @mutex = Mutex.new
        @lifecycle_monitor = Monitor.new
        @pending_ids = Set.new
      end

      def register(manifest = nil, **attributes)
        @lifecycle_monitor.synchronize do
          manifest = resolve_manifest(manifest, attributes)
          permission_contributions = PermissionContributionLoader.load(manifest)
          contributions = ContributionDocumentLoader.load(manifest)
          definition = Definition.new(
            manifest,
            event_bus:,
            capability_auditor: ->(capability) { audit_capability_use(manifest, capability) },
            permission_contributions:,
            permission_catalog: @permission_catalog,
            contributions:
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
          @permission_catalog.clear
          @contribution_catalog.clear

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
            next unless activate_permission_contributions(definition)
            next unless activate_contributions(definition)

            definition.mark_active!(order: activation_index)
            activation_index += 1
            audit_listener_capabilities(definition)
            audit_filter_capabilities(definition)
            audit_service_decorator_capabilities(definition)
            audit_fulfillment_provider_capabilities(definition)
          end

          subscribe_to_active_events!
          list
        end
      end

      def reset!
        @lifecycle_monitor.synchronize do
          unsubscribe_all!
          @permission_catalog.clear
          @contribution_catalog.clear
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
          @permission_catalog.deactivate(id)
          @contribution_catalog.deactivate(id)
        end
      end

      def list
        definition_snapshot.sort_by(&:id).map(&:to_h).freeze
      end

      def ids
        @mutex.synchronize { @definitions.keys.sort.freeze }
      end

      def permission_contributions
        @permission_catalog.all.map(&:to_h).freeze
      end

      def permission_contribution(id)
        @permission_catalog.find(id)&.to_h
      end

      def contributions(type: nil)
        active_definitions = definition_snapshot.select(&:dispatchable?)
        generic = @contribution_catalog.all(type:).map { |entry| entry.to_h.except(:source) }
        legacy = active_definitions.flat_map(&:legacy_contribution_descriptors)
        legacy.select! { |entry| entry.fetch(:type) == type.to_s } if type
        (generic + legacy).sort_by do |entry|
          [
            entry.fetch(:priority),
            entry.fetch(:type),
            entry.fetch(:plugin_id),
            entry.fetch(:id)
          ]
        end.freeze
      end

      def contributions_for(plugin_id)
        generic = @contribution_catalog.for_plugin(plugin_id).map { |entry| entry.to_h.except(:source) }
        definition = definition_for(plugin_id.to_s)
        legacy = definition&.dispatchable? ? definition.legacy_contribution_descriptors : []
        (generic + legacy).sort_by do |entry|
          [
            entry.fetch(:priority),
            entry.fetch(:type),
            entry.fetch(:plugin_id),
            entry.fetch(:id)
          ]
        end.freeze
      end

      def settings_catalog
        definition_snapshot.sort_by(&:id).filter_map do |definition|
          next unless definition.settings_schema

          {
            plugin_id: definition.id,
            plugin_name: definition.manifest.name,
            plugin_version: definition.manifest.version,
            status: definition.status.to_s,
            schema: definition.settings_schema
          }.freeze
        end.freeze
      end

      def settings_schema(plugin_id)
        definition = definition_for(plugin_id.to_s)
        definition&.settings_schema
      end

      def fulfillment_providers
        definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:fulfillment_provider_descriptors)
          .sort_by { |provider| provider.fetch(:id) }
          .freeze
      end

      # Invokes an active provider across the stable plugin boundary. Both the
      # request and the validated response are deeply immutable JSON-like
      # values, and provider failures are sanitized before reaching commerce
      # persistence or customer-facing surfaces.
      def dispatch_fulfillment(provider_id:, request:)
        provider_id = provider_id.to_s
        unless provider_id.match?(FULFILLMENT_PROVIDER_ID_PATTERN)
          raise FulfillmentProviderError.new(
            code: "provider_invalid",
            message: "fulfillment provider id is invalid"
          )
        end

        plugin_id, key = provider_id.split(":", 2)
        definition = definition_for(plugin_id)
        provider = definition&.dispatchable? && definition.fulfillment_provider_handler(key)
        unless provider
          raise FulfillmentProviderError.new(
            code: "provider_unavailable",
            message: "fulfillment provider is not active"
          )
        end

        immutable_request = Mcweb::PluginApi::V1::Normalizer.call(request)
        candidate = Mcweb::PluginApi::V1::Normalizer.call(
          provider.callback.call(immutable_request)
        )
        validate_fulfillment_result(candidate)
      rescue FulfillmentProviderError => error
        if error.code == "provider_response_invalid" && definition
          definition.record_extension_failure!(error)
          record_diagnostic(
            level: :error,
            code: :fulfillment_provider_response_invalid,
            phase: :fulfillment,
            plugin_id: definition.id,
            event: provider_id,
            message: error.message,
            exception: error
          )
        end
        raise
      rescue StandardError => error
        sanitized_error = FulfillmentProviderError.new(
          code: "provider_failed",
          message: "fulfillment provider failed"
        )
        definition&.record_extension_failure!(sanitized_error)
        record_diagnostic(
          level: :error,
          code: :fulfillment_provider_error,
          phase: :fulfillment,
          plugin_id: definition&.id,
          event: provider_id,
          message: sanitized_error.message,
          exception: error
        )
        raise sanitized_error
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

      # Runs a core operation through deterministic, synchronous service
      # decorators. Each decorator receives a memoized continuation plus
      # immutable, normalized input and context:
      #
      #   plugin.decorate_service("forum.topic.create") do |proceed, input, context|
      #     result = proceed.call(input.merge("title" => "[Plugin] #{input.fetch('title')}"))
      #     result
      #   end
      #
      # A decorator cannot suppress the core operation: omitting +proceed+,
      # raising, or returning an incompatible root type is diagnosed and falls
      # back to the downstream result. Exceptions raised by the core operation
      # are never attributed to a plugin and still propagate to the caller.
      # Results deliberately remain host-native (for example ServiceResult or
      # an Active Record object) rather than being serialized or frozen; the
      # stable boundary requires decorators to preserve their exact root class.
      def call_service(name, input: {}, context: {}, &operation)
        raise ArgumentError, "core service operation is required" unless operation

        stack_pushed = false
        name = normalize_service_name(name)
        normalized_input = Mcweb::PluginApi::V1::Normalizer.call(input)
        immutable_context = Mcweb::PluginApi::V1::Normalizer.call(context)
        service_stack = Thread.current.thread_variable_get(service_stack_key) || []

        if service_stack.include?(name)
          record_diagnostic(
            level: :error,
            code: :service_recursion,
            phase: :service,
            event: name,
            message: "recursive service decoration was bypassed"
          )
          return operation.call(normalized_input, immutable_context)
        end

        Thread.current.thread_variable_set(service_stack_key, service_stack + [ name ])
        stack_pushed = true
        invoke_service_decorator(
          name:,
          decorators: service_decorators_for(name),
          index: 0,
          input: normalized_input,
          context: immutable_context,
          operation:
        )
      ensure
        Thread.current.thread_variable_set(service_stack_key, service_stack) if stack_pushed
      end

      def dispatch_job(
        plugin_id:,
        plugin_version:,
        contribution_schema_version:,
        declaration_digest:,
        job_key:,
        arguments:,
        context:
      )
        plugin_id = plugin_id.to_s
        job_key = job_key.to_s
        definition = definition_for(plugin_id)
        unless definition&.dispatchable?
          raise JobDispatchError.new(
            code: "plugin_unavailable",
            message: "plugin job owner is not active"
          )
        end

        contribution = definition.job_contribution
        declaration = contribution&.jobs&.[](job_key)
        unless definition.manifest.version == plugin_version.to_s &&
            contribution&.version == contribution_schema_version.to_s &&
            declaration&.digest == declaration_digest.to_s
          raise JobDispatchError.new(
            code: "incompatible_job",
            message: "plugin job payload is incompatible with the active plugin release"
          )
        end

        handler = definition.job_handler(job_key)
        unless handler
          raise JobDispatchError.new(
            code: "handler_unavailable",
            message: "plugin job handler is not registered"
          )
        end

        normalized_arguments = begin
          declaration.validate_arguments(arguments)
        rescue JobValidationError
          raise JobDispatchError.new(
            code: "job_payload_invalid",
            message: "persisted plugin job arguments failed declaration validation"
          )
        end
        handler.callback.call(normalized_arguments, context)
      rescue JobDispatchError
        raise
      rescue StandardError
        sanitized_error = JobDispatchError.new(
          code: "handler_failed",
          message: "plugin job handler failed"
        )
        definition&.record_job_failure!(sanitized_error)
        record_diagnostic(
          level: :error,
          code: :job_handler_error,
          phase: :job,
          plugin_id:,
          event: job_key,
          message: sanitized_error.message,
          exception: sanitized_error
        )
        raise sanitized_error
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

      def activate_permission_contributions(definition)
        conflicts = @permission_catalog.activate(definition.permission_contributions)
        return true if conflicts.empty?

        definition.mark_disabled!("permission contribution conflict")
        conflicts.each do |conflict|
          record_diagnostic(
            level: :error,
            code: :permission_contribution_conflict,
            phase: :activation,
            plugin_id: definition.id,
            message: "#{conflict.type} #{conflict.value} is already owned by " \
              "#{conflict.existing_plugin_id}"
          )
        end
        false
      end

      def activate_contributions(definition)
        conflicts = @contribution_catalog.activate(definition.contributions)
        return true if conflicts.empty?

        @permission_catalog.deactivate(definition.id)
        definition.mark_disabled!("plugin contribution conflict")
        conflicts.each do |conflict|
          record_diagnostic(
            level: :error,
            code: :"contribution_#{conflict.code}",
            phase: :activation,
            plugin_id: definition.id,
            event: conflict.contribution_id,
            message: [
              conflict.code,
              conflict.contribution_id,
              conflict.other_plugin_id,
              conflict.other_contribution_id,
              conflict.recommendation
            ].compact.join(" · ")
          )
        end
        false
      end

      def audit_listener_capabilities(definition)
        definition.listeners
          .map { |listener| "#{listener.event.split('.', 2).first}.events.read" }
          .uniq
          .sort
          .each do |capability|
            next if definition.declares_capability?(capability)

            record_diagnostic(
              level: :warning,
              code: :undeclared_capability,
              phase: :activation,
              plugin_id: definition.id,
              message: "event listeners are registered without declaring " \
                "#{capability}; allowed because plugins are fully trusted"
            )
          end
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

      def audit_service_decorator_capabilities(definition)
        definition.service_decorators
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
              message: "service decorators are registered without declaring #{capability}; allowed because plugins are fully trusted"
            )
          end
      end

      def audit_fulfillment_provider_capabilities(definition)
        return if definition.fulfillment_provider_descriptors.empty?
        return if definition.declares_capability?(FULFILLMENT_PROVIDER_CAPABILITY)

        record_diagnostic(
          level: :warning,
          code: :undeclared_capability,
          phase: :activation,
          plugin_id: definition.id,
          message: "fulfillment providers are registered without declaring " \
            "#{FULFILLMENT_PROVIDER_CAPABILITY}; allowed because plugins are fully trusted"
        )
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

      def normalize_service_name(name)
        normalized = name.to_s
        unless normalized.length <= Definition::MAX_EVENT_NAME_LENGTH &&
            normalized.match?(Definition::EVENT_PATTERN)
          raise ArgumentError, "invalid service name #{normalized.inspect}"
        end
        normalized
      end

      def validate_fulfillment_result(candidate)
        unless candidate.is_a?(Hash)
          raise FulfillmentProviderError.new(
            code: "provider_response_invalid",
            message: "fulfillment provider response must be a mapping"
          )
        end

        allowed_keys = %w[status external_reference error_code]
        unless (candidate.keys - allowed_keys).empty?
          raise FulfillmentProviderError.new(
            code: "provider_response_invalid",
            message: "fulfillment provider response contains unsupported fields"
          )
        end

        status = candidate["status"].to_s
        unless FULFILLMENT_RESULT_STATUSES.include?(status)
          raise FulfillmentProviderError.new(
            code: "provider_response_invalid",
            message: "fulfillment provider response status is invalid"
          )
        end

        external_reference = candidate["external_reference"]
        if external_reference.present? && (
          !external_reference.is_a?(String) ||
          external_reference.length > 200
        )
          raise FulfillmentProviderError.new(
            code: "provider_response_invalid",
            message: "fulfillment provider external reference is invalid"
          )
        end

        error_code = candidate["error_code"]
        if status != "succeeded" && (
          !error_code.is_a?(String) ||
          !error_code.match?(/\A[a-z0-9_.-]{1,100}\z/)
        )
          raise FulfillmentProviderError.new(
            code: "provider_response_invalid",
            message: "fulfillment provider error code is invalid"
          )
        end

        {
          "status" => status,
          "external_reference" => external_reference,
          "error_code" => error_code
        }.compact.freeze
      end

      def filters_for(name)
        definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:filters)
          .select { |filter| filter.name == name }
          .sort_by { |filter| [ filter.priority, filter.plugin_id, filter.sequence ] }
      end

      def service_decorators_for(name)
        definition_snapshot
          .select(&:dispatchable?)
          .flat_map(&:service_decorators)
          .select { |decorator| decorator.name == name }
          .sort_by { |decorator| [ decorator.priority, decorator.plugin_id, decorator.sequence ] }
      end

      def invoke_service_decorator(name:, decorators:, index:, input:, context:, operation:)
        decorator = decorators[index]
        return operation.call(input, context) unless decorator

        continuation = ServiceContinuation.new(
          default_input: input,
          normalizer: Mcweb::PluginApi::V1::Normalizer.method(:call),
          input_validator: lambda do |candidate|
            next if compatible_service_value?(input, candidate)

            raise LifecycleError,
              "service continuation changed the root input type from " \
                "#{service_value_type_label(input)} to #{service_value_type_label(candidate)}"
          end
        ) do |next_input|
          with_service_stack(name) do
            invoke_service_decorator(
              name:,
              decorators:,
              index: index + 1,
              input: next_input,
              context:,
              operation:
            )
          end
        end

        begin
          candidate = decorator.callback.call(continuation, input, context)
          unless continuation.called?
            error = LifecycleError.new("service decorator must call its continuation")
            definition_for(decorator.plugin_id)&.record_service_decorator_failure!(error)
            record_diagnostic(
              level: :error,
              code: :service_decorator_skipped_core,
              phase: :service,
              plugin_id: decorator.plugin_id,
              event: name,
              message: error.message,
              exception: error
            )
            return continuation.call
          end

          downstream = continuation.result
          if continuation.calls > 1
            record_diagnostic(
              level: :warning,
              code: :service_decorator_multiple_proceed,
              phase: :service,
              plugin_id: decorator.plugin_id,
              event: name,
              message: "service continuation was called #{continuation.calls} times; the downstream operation ran once"
            )
          end

          unless compatible_service_value?(downstream, candidate)
            record_diagnostic(
              level: :error,
              code: :invalid_service_decorator_result,
              phase: :service,
              plugin_id: decorator.plugin_id,
              event: name,
              message: "service decorator changed the root result type from " \
                "#{service_value_type_label(downstream)} to #{service_value_type_label(candidate)}"
            )
            return downstream
          end

          candidate
        rescue StandardError, SystemStackError => e
          raise if continuation.failed_with?(e)

          definition_for(decorator.plugin_id)&.record_service_decorator_failure!(e)
          record_diagnostic(
            level: :error,
            code: :service_decorator_error,
            phase: :service,
            plugin_id: decorator.plugin_id,
            event: name,
            message: e.message,
            exception: e
          )
          logger&.error("[mcweb.plugins] #{decorator.plugin_id} service decorator #{name} failed: #{e.class}: #{e.message}")
          continuation.call
        end
      end

      def compatible_filter_value?(current, candidate)
        filter_value_type(current) == filter_value_type(candidate)
      end

      def compatible_service_value?(current, candidate)
        service_value_type(current) == service_value_type(candidate)
      end

      def service_value_type_label(value)
        type = service_value_type(value)
        return type unless type.is_a?(Class)

        type.name.to_s.empty? ? type.inspect : type.name
      end

      def service_value_type(value)
        case value
        when Hash then :hash
        when Array then :array
        when String then :string
        when Numeric then :number
        when TrueClass, FalseClass then :boolean
        when NilClass then :null
        else value.class
        end
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

      def service_stack_key
        @service_stack_key ||= :"mcweb_plugin_service_stack_#{object_id}"
      end

      def with_service_stack(name)
        service_stack = Thread.current.thread_variable_get(service_stack_key) || []
        added = !service_stack.include?(name)
        Thread.current.thread_variable_set(service_stack_key, service_stack + [ name ]) if added
        yield
      ensure
        Thread.current.thread_variable_set(service_stack_key, service_stack) if added
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

      def permission_contributions
        registry.permission_contributions
      end

      def permission_contribution(id)
        registry.permission_contribution(id)
      end

      def contributions(type: nil)
        registry.contributions(type:)
      end

      def contributions_for(plugin_id)
        registry.contributions_for(plugin_id)
      end

      def settings_catalog
        registry.settings_catalog
      end

      def settings_schema(plugin_id)
        registry.settings_schema(plugin_id)
      end

      def fulfillment_providers
        registry.fulfillment_providers
      end

      def apply_filter(name, value, context: {})
        registry.apply_filter(name, value, context:)
      end

      def call_service(name, input: {}, context: {}, &operation)
        registry.call_service(name, input:, context:, &operation)
      end

      def dispatch_job(**attributes)
        registry.dispatch_job(**attributes)
      end

      def dispatch_fulfillment(**attributes)
        registry.dispatch_fulfillment(**attributes)
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
