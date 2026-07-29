# frozen_string_literal: true

require "socket"
require "securerandom"
require "monitor"
require_relative "lifecycle_error"

module Mcweb
  module Plugins
    # Coordinates the desired plugin set across long-lived Rails and worker
    # processes. Generations are persisted before reload, each process records
    # an explicit health acknowledgement, and a failed or timed-out generation
    # publishes the previous desired set as a rollback generation.
    class GenerationCoordinator
      DEFAULT_TIMEOUT = 45.seconds
      HEARTBEAT_TTL = 5.minutes
      HEARTBEAT_INTERVAL = 30.seconds
      ERROR_MESSAGE_LIMIT = 1_000

      class << self
        def process_uid
          process_identity_mutex.synchronize do
            if @process_identity_pid != Process.pid
              @process_identity_pid = Process.pid
              @process_uid = [
                ENV["MCWEB_PROCESS_ID"].presence || Socket.gethostname,
                Process.pid,
                SecureRandom.hex(6)
              ].join(":").freeze
            end
            @process_uid
          end
        end

        private

        def process_identity_mutex
          @process_identity_mutex ||= Mutex.new
        end
      end

      def initialize(
        clock: -> { Time.current },
        reloader: -> { Mcweb::Plugins.reload! },
        runtime_catalog: -> { Mcweb::Plugins.list },
        process_uid: nil,
        process_kind: nil,
        hostname: nil,
        pid: nil
      )
        @clock = clock
        @reloader = reloader
        @runtime_catalog = runtime_catalog
        @process_uid = process_uid&.to_s || self.class.process_uid
        @process_kind = process_kind&.to_s
        @hostname = (hostname || Socket.gethostname).to_s
        @pid = pid || Process.pid
        @reconcile_monitor = Monitor.new
        @last_heartbeat_at = nil
        @last_generation_number = nil
      end

      def available?
        ActiveRecord::Base.connection.data_source_exists?("plugin_generations") &&
          ActiveRecord::Base.connection.data_source_exists?("plugin_process_acks")
      rescue ActiveRecord::ActiveRecordError
        false
      end

      def publish!(
        desired_plugins:,
        action:,
        target_plugin_id: nil,
        operation_id: nil,
        actor: nil,
        previous_plugins: nil,
        timeout: DEFAULT_TIMEOUT,
        minimum_ack_ratio: 1,
        wait_for_acknowledgements: false
      )
        return unless available?

        desired = normalize_plugin_versions(desired_plugins)
        timeout = normalize_timeout(timeout)
        ratio = normalize_ratio(minimum_ack_ratio)
        generation = PluginGeneration.transaction do
          latest = PluginGeneration.lock.ordered.first
          previous = previous_plugins.nil? ? latest&.desired_plugins || {} :
            normalize_plugin_versions(previous_plugins)
          expected = recent_process_uids
          expected << @process_uid
          PluginGeneration.create!(
            number: latest&.number.to_i + 1,
            state: "pending",
            action: action.to_s,
            target_plugin_id: target_plugin_id.to_s.presence,
            operation_id: operation_id.to_s.presence,
            initiated_by: actor,
            desired_plugins: desired,
            previous_plugins: previous,
            expected_process_uids: expected.uniq.sort,
            minimum_ack_ratio: ratio,
            deadline_at: @clock.call + timeout
          )
        end

        reconcile!(generation:, process_kind: current_process_kind)
        PluginGenerationMonitorJob.set(wait: timeout).perform_later(generation.id)
        generation = generation.reload
        return generation unless wait_for_acknowledgements

        wait_for_resolution!(generation, timeout:)
      end

      def reconcile_current_process!(process_kind:)
        return unless available?

        @process_kind = normalize_process_kind(process_kind)
        generation = PluginGeneration.actionable.or(
          PluginGeneration.where(state: "active")
        ).ordered.first
        return unless generation

        @reconcile_monitor.synchronize do
          now = @clock.call
          if @last_generation_number == generation.number &&
              @last_heartbeat_at &&
              @last_heartbeat_at > now - HEARTBEAT_INTERVAL
            return generation
          end

          reconcile!(
            generation:,
            process_kind: normalize_process_kind(process_kind),
            reload: @last_generation_number != generation.number
          )
          @last_generation_number = generation.number
          @last_heartbeat_at = now
        end
        generation
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def reconcile!(generation:, process_kind:, reload: true)
        process_kind = normalize_process_kind(process_kind)
        @reloader.call if reload
        actual = runtime_plugin_versions
        desired = normalize_plugin_versions(generation.desired_plugins)
        if actual == desired
          acknowledge!(
            generation:,
            process_kind:,
            status: "healthy",
            plugin_versions: actual
          )
        else
          acknowledge!(
            generation:,
            process_kind:,
            status: "failed",
            plugin_versions: actual,
            error_code: "generation_mismatch",
            error_message: version_mismatch_message(desired:, actual:)
          )
        end
        finalize!(generation.id)
      rescue StandardError, ScriptError => e
        acknowledge!(
          generation:,
          process_kind:,
          status: "failed",
          plugin_versions: safe_runtime_plugin_versions,
          error_code: "reload_failed",
          error_message: safe_error_message(e)
        )
        finalize!(generation.id)
      end

      def finalize!(generation_id)
        return unless available?

        generation = nil
        rollback = false
        PluginGeneration.transaction do
          generation = PluginGeneration.lock.find(generation_id)
          next generation if generation.terminal?

          acknowledgements = generation.process_acks.reload.to_a
          expected = Array(generation.expected_process_uids).map(&:to_s).uniq
          expected = acknowledgements.map(&:process_uid).uniq if expected.empty?
          healthy = acknowledgements.count do |ack|
            ack.status == "healthy" && expected.include?(ack.process_uid)
          end
          required = [ (expected.length * generation.minimum_ack_ratio.to_d).ceil, 1 ].max
          failed = acknowledgements.find do |ack|
            ack.status == "failed" && expected.include?(ack.process_uid)
          end

          if failed
            if generation.action == "rollback"
              generation.update!(
                state: "failed",
                error_code: failed.error_code.presence || "rollback_process_failed",
                error_message: safe_text(failed.error_message)
              )
            else
              generation.update!(
                state: "rolling_back",
                rollback_started_at: @clock.call,
                error_code: failed.error_code.presence || "process_reload_failed",
                error_message: safe_text(failed.error_message)
              )
              rollback = true
            end
          elsif healthy >= required
            PluginGeneration.where(state: "active").where.not(id: generation.id)
              .update_all(state: "superseded", updated_at: @clock.call)
            generation.update!(state: "active", activated_at: @clock.call)
          elsif @clock.call >= generation.deadline_at
            if generation.action == "rollback"
              generation.update!(
                state: "failed",
                error_code: "rollback_ack_timeout",
                error_message: "only #{healthy} of #{required} required processes acknowledged rollback"
              )
            else
              generation.update!(
                state: "rolling_back",
                rollback_started_at: @clock.call,
                error_code: "ack_timeout",
                error_message: "only #{healthy} of #{required} required processes acknowledged"
              )
              rollback = true
            end
          end
        end
        rollback ? publish_rollback!(generation) : generation.reload
      end

      private

      def wait_for_resolution!(generation, timeout:)
        monotonic_deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) +
          timeout.in_seconds
        loop do
          generation.reload
          return generation if generation.state == "active"
          if generation.state.in?(%w[rolled_back failed])
            raise LifecycleError,
              "plugin generation #{generation.number} failed and runtime rollback was requested"
          end

          if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= monotonic_deadline
            generation = finalize!(generation.id)
            return generation if generation.state == "active"

            raise LifecycleError,
              "plugin generation #{generation.number} did not reach the required acknowledgements"
          end
          sleep 0.1
        end
      end

      def publish_rollback!(failed_generation)
        rollback = PluginGeneration.transaction do
          failed_generation.lock!
          existing = PluginGeneration.find_by(parent_generation_id: failed_generation.id, action: "rollback")
          next existing if existing

          latest = PluginGeneration.lock.ordered.first
          PluginGeneration.create!(
            number: latest&.number.to_i + 1,
            state: "pending",
            action: "rollback",
            target_plugin_id: failed_generation.target_plugin_id,
            operation_id: failed_generation.operation_id,
            initiated_by: failed_generation.initiated_by,
            parent_generation: failed_generation,
            desired_plugins: failed_generation.previous_plugins,
            previous_plugins: failed_generation.desired_plugins,
            expected_process_uids: failed_generation.expected_process_uids,
            minimum_ack_ratio: failed_generation.minimum_ack_ratio,
            deadline_at: @clock.call + DEFAULT_TIMEOUT
          )
        end
        failed_generation.update!(state: "rolled_back", rolled_back_at: @clock.call)
        reconcile!(generation: rollback, process_kind: current_process_kind)
        PluginGenerationMonitorJob.set(wait: DEFAULT_TIMEOUT).perform_later(rollback.id)
        rollback
      rescue StandardError => e
        failed_generation.update!(
          state: "failed",
          error_code: "rollback_failed",
          error_message: safe_error_message(e)
        )
        failed_generation
      end

      def acknowledge!(
        generation:,
        process_kind:,
        status:,
        plugin_versions:,
        error_code: nil,
        error_message: nil
      )
        now = @clock.call
        ack = PluginProcessAck.find_or_initialize_by(
          plugin_generation: generation,
          process_uid: @process_uid
        )
        ack.assign_attributes(
          process_kind:,
          process_pid: @pid,
          hostname: @hostname,
          status:,
          plugin_versions: normalize_plugin_versions(plugin_versions),
          error_code: error_code.to_s.presence,
          error_message: safe_text(error_message),
          acked_at: now,
          last_seen_at: now
        )
        ack.save!
        ack
      end

      def runtime_plugin_versions
        normalize_plugin_versions(
          Array(@runtime_catalog.call).filter_map do |entry|
            data = entry.respond_to?(:to_h) ? entry.to_h : {}
            status = data[:status] || data["status"]
            next unless status.to_s.in?(%w[active degraded])

            id = data[:id] || data["id"]
            version = data[:version] || data["version"]
            [ id, version ]
          end.to_h
        )
      end

      def safe_runtime_plugin_versions
        runtime_plugin_versions
      rescue StandardError
        {}
      end

      def recent_process_uids
        PluginProcessAck
          .where("last_seen_at >= ?", @clock.call - HEARTBEAT_TTL)
          .distinct
          .pluck(:process_uid)
      end

      def normalize_plugin_versions(value)
        pairs =
          case value
          when Hash
            value.to_a
          else
            Array(value).map do |entry|
              data = entry.respond_to?(:to_h) ? entry.to_h : {}
              [ data[:id] || data["id"], data[:version] || data["version"] ]
            end
          end
        pairs.each_with_object({}) do |(raw_id, raw_version), result|
          id = raw_id.to_s
          version = raw_version.to_s
          next if id.blank? || version.blank?

          result[id] = version
        end.sort.to_h.freeze
      end

      def normalize_process_kind(value)
        kind = value.to_s
        PluginProcessAck::PROCESS_KINDS.include?(kind) ? kind : "other"
      end

      def current_process_kind
        normalize_process_kind(
          @process_kind.presence ||
          ENV["MCWEB_PROCESS_KIND"].presence ||
          "other"
        )
      end

      def normalize_timeout(value)
        seconds = value.respond_to?(:in_seconds) ? value.in_seconds : Float(value)
        raise ArgumentError, "generation timeout must be between 1 and 600 seconds" unless seconds.between?(1, 600)

        seconds.seconds
      rescue ArgumentError, TypeError
        raise ArgumentError, "generation timeout must be between 1 and 600 seconds"
      end

      def normalize_ratio(value)
        ratio = BigDecimal(value.to_s)
        raise ArgumentError, "minimum acknowledgement ratio must be within (0, 1]" unless ratio.positive? && ratio <= 1

        ratio
      rescue ArgumentError
        raise ArgumentError, "minimum acknowledgement ratio must be within (0, 1]"
      end

      def version_mismatch_message(desired:, actual:)
        missing = desired.keys - actual.keys
        unknown = actual.keys - desired.keys
        mismatched = desired.keys.select do |id|
          actual.key?(id) && desired.fetch(id) != actual.fetch(id)
        end
        safe_text(
          "missing=#{missing.sort.join(',')} unknown=#{unknown.sort.join(',')} " \
          "mismatched=#{mismatched.sort.join(',')}"
        )
      end

      def safe_error_message(error)
        safe_text("#{error.class}: #{error.message}")
      end

      def safe_text(value)
        value.to_s.gsub(/(token|secret|password|authorization)\s*[=:]\s*\S+/i, "\\1=[REDACTED]")
          .slice(0, ERROR_MESSAGE_LIMIT)
          .presence
      end
    end

    class << self
      def generation_coordinator
        @generation_coordinator ||= GenerationCoordinator.new
      end

      def reset_generation_coordinator!
        @generation_coordinator = nil
      end
    end
  end
end
