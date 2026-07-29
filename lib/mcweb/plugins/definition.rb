# frozen_string_literal: true

require_relative "../plugin_api/v1/host"

module Mcweb
  module Plugins
    Listener = Data.define(:plugin_id, :event, :priority, :sequence, :callback)
    Filter = Data.define(:plugin_id, :name, :priority, :sequence, :callback)
    ServiceDecorator = Data.define(:plugin_id, :name, :priority, :sequence, :callback)
    JobHandler = Data.define(:plugin_id, :job_key, :callback)
    FulfillmentProvider = Data.define(:plugin_id, :key, :provider_id, :callback)

    class Definition
      EVENT_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      FULFILLMENT_PROVIDER_KEY_PATTERN = /\A[a-z][a-z0-9_.-]{0,63}\z/
      MAX_EVENT_NAME_LENGTH = 191
      PRIORITY_RANGE = (-10_000..10_000)

      attr_reader :manifest, :api, :job_contribution, :permission_contributions,
                  :settings_schema, :contributions

      def initialize(
        manifest,
        event_bus: Mcweb::Events,
        capability_auditor: nil,
        permission_contributions: [],
        permission_catalog: nil,
        contributions: []
      )
        @manifest = manifest
        @permission_contributions = permission_contributions.dup.freeze
        @contributions = contributions.dup.freeze
        @api = Mcweb::PluginApi::V1::Host.new(
          manifest:,
          event_bus:,
          capability_auditor:,
          permission_catalog:
        )
        @job_contribution = @api.jobs.declaration
        @settings_schema = @api.settings.declaration
        @listeners = []
        @filters = []
        @service_decorators = []
        @job_handlers = {}
        @fulfillment_providers = {}
        @sealed = false
        @status = :registered
        @failure_count = 0
        @last_error = nil
        @activation_order = nil
        @mutex = Mutex.new
      end

      def id
        manifest.id
      end

      # Capabilities are declarations for compatibility and audit. Plugins are
      # fully trusted Ruby code; this API is deliberately not a sandbox.
      def on(event, priority: 100, &callback)
        raise ArgumentError, "listener callback is required" unless callback

        event = normalize_extension_name(event, label: "event")
        validate_priority!(priority)

        @mutex.synchronize do
          raise LifecycleError, "plugin definition is sealed" if @sealed

          @listeners << Listener.new(
            plugin_id: id,
            event: event.freeze,
            priority: priority,
            sequence: @listeners.length,
            callback:
          )
        end
        self
      end

      # Synchronous filters are the stable alternative to monkey-patching core
      # services. Every callback receives an immutable, normalized value and
      # context and must return the next value in the chain. The registry keeps
      # ordering deterministic and isolates a failing plugin.
      def filter(name, priority: 100, &callback)
        raise ArgumentError, "filter callback is required" unless callback

        name = normalize_extension_name(name, label: "filter")
        validate_priority!(priority)

        @mutex.synchronize do
          raise LifecycleError, "plugin definition is sealed" if @sealed

          @filters << Filter.new(
            plugin_id: id,
            name: name.freeze,
            priority: priority,
            sequence: @filters.length,
            callback:
          )
        end
        self
      end

      # Around-service decorators are the stable alternative to prepending or
      # monkey-patching a core service. The continuation passed to the callback
      # is memoized and the registry guarantees that the core operation still
      # runs exactly once when a decorator raises or forgets to continue.
      def decorate_service(name, priority: 100, &callback)
        raise ArgumentError, "service decorator callback is required" unless callback

        name = normalize_extension_name(name, label: "service")
        validate_priority!(priority)

        @mutex.synchronize do
          raise LifecycleError, "plugin definition is sealed" if @sealed

          @service_decorators << ServiceDecorator.new(
            plugin_id: id,
            name: name.freeze,
            priority: priority,
            sequence: @service_decorators.length,
            callback:
          )
        end
        self
      end

      # Jobs are addressed only by keys declared in contributions.jobs. The
      # callback is retained by the trusted runtime registry; no Ruby class name
      # crosses the persistent queue boundary.
      def job(job_key, &callback)
        raise ArgumentError, "job callback is required" unless callback

        normalized_key = normalize_job_key(job_key)
        @mutex.synchronize do
          raise LifecycleError, "plugin definition is sealed" if @sealed
          unless job_contribution
            raise LifecycleError, "plugin #{id} does not declare a jobs contribution"
          end
          job_contribution.fetch(normalized_key)
          if @job_handlers.key?(normalized_key)
            raise LifecycleError, "plugin job #{id}:#{normalized_key} is already registered"
          end

          @job_handlers[normalized_key] = JobHandler.new(
            plugin_id: id,
            job_key: normalized_key,
            callback:
          )
        end
        self
      end

      # Registers a synchronous commerce fulfillment provider owned by this
      # plugin. Products address it by the stable, namespaced provider id
      # "<plugin-id>:<key>". The callback receives only an immutable,
      # allow-listed request and must return a strict status mapping.
      def fulfillment_provider(key, &callback)
        raise ArgumentError, "fulfillment provider callback is required" unless callback

        normalized_key = key.to_s.dup
        unless normalized_key.match?(FULFILLMENT_PROVIDER_KEY_PATTERN)
          raise ArgumentError, "invalid fulfillment provider key #{normalized_key.inspect}"
        end
        normalized_key.freeze
        provider_id = "#{id}:#{normalized_key}".freeze

        @mutex.synchronize do
          raise LifecycleError, "plugin definition is sealed" if @sealed
          if @fulfillment_providers.key?(normalized_key)
            raise LifecycleError, "plugin fulfillment provider #{provider_id} is already registered"
          end

          @fulfillment_providers[normalized_key] = FulfillmentProvider.new(
            plugin_id: id,
            key: normalized_key,
            provider_id:,
            callback:
          )
        end
        self
      end

      def listeners
        @mutex.synchronize { @listeners.dup.freeze }
      end

      def filters
        @mutex.synchronize { @filters.dup.freeze }
      end

      def service_decorators
        @mutex.synchronize { @service_decorators.dup.freeze }
      end

      def job_handler(job_key)
        @mutex.synchronize { @job_handlers[job_key.to_s] }
      end

      def job_handler_keys
        @mutex.synchronize { @job_handlers.keys.sort.freeze }
      end

      def fulfillment_provider_handler(key)
        @mutex.synchronize { @fulfillment_providers[key.to_s] }
      end

      def fulfillment_provider_descriptors
        @mutex.synchronize do
          @fulfillment_providers.values.sort_by(&:provider_id).map do |provider|
            {
              id: provider.provider_id,
              key: provider.key,
              plugin_id: provider.plugin_id,
              plugin_name: manifest.name,
              plugin_version: manifest.version
            }.freeze
          end.freeze
        end
      end

      def legacy_contribution_descriptors
        descriptors = permission_contributions.map do |entry|
          {
            plugin_id: id,
            type: "permission",
            id: entry.id,
            priority: 100,
            before: [],
            after: [],
            requires: [],
            conflicts: [],
            payload: entry.to_h.except(:plugin_id)
          }.freeze
        end
        if settings_schema
          descriptors << {
            plugin_id: id,
            type: "settings",
            id: "#{id.tr('/-', '._')}.settings.schema",
            priority: 100,
            before: [],
            after: [],
            requires: [],
            conflicts: [],
            payload: {
              schema_version: settings_schema.version,
              groups: settings_schema.groups.keys,
              fields: settings_schema.properties.keys,
              required_fields: settings_schema.required_keys
            }
          }.freeze
        end
        if job_contribution
          job_contribution.jobs.each_value do |job|
            descriptors << {
              plugin_id: id,
              type: "job",
              id: "#{id.tr('/-', '._')}.job.#{job.key.tr('.', '_')}",
              priority: 100,
              before: [],
              after: [],
              requires: [],
              conflicts: [],
              payload: {
                key: job.key,
                max_attempts: job.max_attempts,
                retry_wait_seconds: job.retry_wait_seconds,
                lease_seconds: job.lease_seconds
              }
            }.freeze
          end
        end
        descriptors.sort_by { |entry| [ entry.fetch(:type), entry.fetch(:id) ] }.freeze
      end

      def contribution_descriptors
        (
          contributions.map { |entry| entry.to_h.except(:source) } +
            legacy_contribution_descriptors
        ).sort_by do |entry|
          [ entry.fetch(:priority), entry.fetch(:type), entry.fetch(:plugin_id), entry.fetch(:id) ]
        end.freeze
      end

      def declares_capability?(capability)
        manifest.capabilities.include?(capability.to_s)
      end

      def status
        @mutex.synchronize { @status }
      end

      def failure_count
        @mutex.synchronize { @failure_count }
      end

      def last_error
        @mutex.synchronize { @last_error }
      end

      def activation_order
        @mutex.synchronize { @activation_order }
      end

      def dispatchable?
        status.in?(%i[active degraded])
      end

      def seal!
        @mutex.synchronize do
          missing_jobs = job_contribution ? job_contribution.jobs.keys - @job_handlers.keys : []
          if missing_jobs.any?
            raise LifecycleError,
              "plugin #{id} is missing handlers for jobs: #{missing_jobs.sort.join(', ')}"
          end

          @sealed = true
          @listeners.freeze
          @filters.freeze
          @service_decorators.freeze
          @job_handlers.freeze
          @fulfillment_providers.freeze
        end
        self
      end

      def mark_registered!
        @mutex.synchronize do
          @status = :registered
          @activation_order = nil
        end
        self
      end

      def mark_active!(order:)
        @mutex.synchronize do
          @status = :active
          @activation_order = order
        end
        self
      end

      def mark_disabled!(message)
        @mutex.synchronize do
          @status = :disabled
          @last_error = message.to_s.dup.freeze
          @activation_order = nil
        end
        self
      end

      def record_listener_failure!(error)
        record_extension_failure!(error)
      end

      def record_filter_failure!(error)
        record_extension_failure!(error)
      end

      def record_service_decorator_failure!(error)
        record_extension_failure!(error)
      end

      def record_job_failure!(error)
        record_extension_failure!(error)
      end

      def record_extension_failure!(error)
        @mutex.synchronize do
          @status = :degraded
          @failure_count += 1
          @last_error = "#{error.class}: #{error.message}".freeze
        end
        self
      end

      def to_h
        state = @mutex.synchronize do
          {
            status: @status.to_s.freeze,
            listener_count: @listeners.length,
            filter_count: @filters.length,
            service_decorator_count: @service_decorators.length,
            job_handler_count: @job_handlers.length,
            fulfillment_provider_count: @fulfillment_providers.length,
            fulfillment_provider_ids: @fulfillment_providers.values.map(&:provider_id).sort.freeze,
            jobs_schema_version: job_contribution&.version,
            permission_contribution_count: permission_contributions.length,
            settings_schema_version: settings_schema&.version,
            contribution_count: contribution_descriptors.length,
            contribution_descriptors: contribution_descriptors,
            failure_count: @failure_count,
            last_error: @last_error,
            activation_order: @activation_order
          }
        end
        manifest.to_h.merge(state).freeze
      end

      private

      def normalize_extension_name(value, label:)
        name = value.to_s.dup
        unless name.length <= MAX_EVENT_NAME_LENGTH && name.match?(EVENT_PATTERN)
          raise ArgumentError, "invalid #{label} name #{name.inspect}"
        end
        name
      end

      def normalize_job_key(value)
        key = value.to_s.dup
        unless key.length <= MAX_EVENT_NAME_LENGTH &&
            key.match?(JobContribution::JOB_KEY_PATTERN)
          raise ArgumentError, "invalid job key #{key.inspect}"
        end
        key.freeze
      end

      def validate_priority!(priority)
        raise ArgumentError, "priority must be an integer" unless priority.is_a?(Integer)
        raise ArgumentError, "priority must be within #{PRIORITY_RANGE}" unless PRIORITY_RANGE.cover?(priority)
      end
    end
  end
end
