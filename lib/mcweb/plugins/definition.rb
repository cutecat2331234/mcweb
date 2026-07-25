# frozen_string_literal: true

require_relative "../plugin_api/v1/host"

module Mcweb
  module Plugins
    Listener = Data.define(:plugin_id, :event, :priority, :sequence, :callback)
    Filter = Data.define(:plugin_id, :name, :priority, :sequence, :callback)

    class Definition
      EVENT_PATTERN = /\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+\z/
      MAX_EVENT_NAME_LENGTH = 191
      PRIORITY_RANGE = (-10_000..10_000)

      attr_reader :manifest, :api

      def initialize(manifest, event_bus: Mcweb::Events, capability_auditor: nil)
        @manifest = manifest
        @api = Mcweb::PluginApi::V1::Host.new(
          manifest:,
          event_bus:,
          capability_auditor:
        )
        @listeners = []
        @filters = []
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

      def listeners
        @mutex.synchronize { @listeners.dup.freeze }
      end

      def filters
        @mutex.synchronize { @filters.dup.freeze }
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
          @sealed = true
          @listeners.freeze
          @filters.freeze
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

      def validate_priority!(priority)
        raise ArgumentError, "priority must be an integer" unless priority.is_a?(Integer)
        raise ArgumentError, "priority must be within #{PRIORITY_RANGE}" unless PRIORITY_RANGE.cover?(priority)
      end
    end
  end
end
