# frozen_string_literal: true

module Operations
  module Metrics
    class Instrumentation
      DEFAULT_SLOW_QUERY_MS = 250
      MIN_SLOW_QUERY_MS = 10
      MAX_SLOW_QUERY_MS = 60_000
      HANDLED_JOB_FAILURES_KEY =
        :mcweb_operations_metrics_handled_job_failures
      ACTION_DURATION_KEY = :mcweb_operations_metrics_action_duration_ms

      COMMUNITY_UPLOAD_EVENTS = {
        "community.upload.reserved" => "reserved",
        "community.upload.stored" => "stored",
        "community.upload.quota_rejected" => "quota_rejected",
        "community.upload.cleaned" => "cleaned",
        "community.upload.cleanup_failed" => "cleanup_failed",
        "community.upload.cleanup_retry_requested" => "cleanup_retry_requested",
        "community.upload.unattached_blob_cleaned" => "unattached_blob_cleaned"
      }.freeze
      COMMUNITY_SCAN_EVENTS = {
        "community.attachment.scan_clean" => "clean",
        "community.attachment.scan_infected" => "infected",
        "community.attachment.scan_error" => "error",
        "community.attachment.scan_retry_requested" => "retry_requested"
      }.freeze

      class << self
        def install!
          @mutex ||= Mutex.new
          @mutex.synchronize do
            return @instance if @instance

            @instance = new
            @instance.install!
          end
          @instance
        end

        def uninstall!
          @mutex ||= Mutex.new
          @mutex.synchronize do
            @instance&.uninstall!
            @instance = nil
          end
        end
      end

      def initialize(
        recorder: -> { ::Operations::Metrics },
        slow_query_ms: configured_slow_query_ms
      )
        @recorder = recorder
        @slow_query_ms = slow_query_ms
        @subscribers = []
      end

      def install!
        return self if @subscribers.any?

        subscribe("process_action.action_controller", :request)
        subscribe("mcweb.request.outer", :outer_request)
        subscribe("sql.active_record", :sql)
        subscribe("perform.active_job", :job)
        subscribe("enqueue_retry.active_job", :job_failure_signal)
        subscribe("retry_stopped.active_job", :job_failure_signal)
        subscribe("discard.active_job", :job_failure_signal)
        subscribe("deliver.action_mailer", :mail)
        subscribe("payments.webhook.processed", :payment_webhook)
        COMMUNITY_UPLOAD_EVENTS.each_key do |name|
          subscribe(name, :community_upload)
        end
        COMMUNITY_SCAN_EVENTS.each_key do |name|
          subscribe(name, :community_scan)
        end
        self
      end

      def uninstall!
        @subscribers.each do |subscriber|
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
        @subscribers.clear
        ActiveSupport::IsolatedExecutionState[HANDLED_JOB_FAILURES_KEY] = nil
      end

      def record_request(event)
        ActiveSupport::IsolatedExecutionState[ACTION_DURATION_KEY] = event.duration
        payload = event.payload
        status = payload[:status].to_i
        status = 500 if status.zero? && event_failed?(payload)
        outcome =
          if status >= 500
            "server_error"
          elsif status >= 400
            "client_error"
          else
            "success"
          end
        dimensions = {
          surface: request_surface(payload[:controller]),
          outcome:
        }
        recorder.record(
          "request.duration_ms",
          value: event.duration,
          dimensions:,
          at: event_time(event)
        )
        return unless status >= 500

        recorder.record(
          "request.server_error",
          dimensions: { surface: dimensions.fetch(:surface) },
          at: event_time(event)
        )
      end

      def record_outer_request(event)
        payload = event.payload
        status = payload[:status].to_i
        outcome = if status >= 500
          "server_error"
        elsif status >= 400
          "client_error"
        else
          "success"
        end
        dimensions = { surface: payload[:surface], outcome: }
        recorded_at = event_time(event)
        recorder.record(
          "request.total_duration_ms",
          value: payload[:duration_ms],
          dimensions:,
          at: recorded_at
        )
        recorder.record(
          "request.queue_duration_ms",
          value: payload[:queue_duration_ms],
          dimensions: { surface: dimensions.fetch(:surface) },
          at: recorded_at
        )
        return if payload[:middleware_duration_ms].nil?

        recorder.record(
          "request.middleware_duration_ms",
          value: payload[:middleware_duration_ms],
          dimensions: { surface: dimensions.fetch(:surface) },
          at: recorded_at
        )
      end

      def record_sql(event)
        payload = event.payload
        return if payload[:cached]
        return if %w[SCHEMA TRANSACTION].include?(payload[:name].to_s.upcase)
        return if event.duration < @slow_query_ms

        recorder.record(
          "database.slow_query.duration_ms",
          value: event.duration,
          at: event_time(event)
        )
      end

      def record_job(event)
        payload = event.payload
        handled_failure = consume_handled_job_failure(payload[:job])
        failed = event_failed?(payload) || handled_failure
        queue = normalized_queue(payload[:job])
        recorder.record(
          "job.execution.duration_ms",
          value: event.duration,
          dimensions: {
            queue:,
            outcome: failed ? "failure" : "success"
          },
          at: event_time(event)
        )
        return unless failed

        recorder.record(
          "job.failure",
          dimensions: { queue: },
          at: event_time(event)
        )
      end

      def record_job_failure_signal(event)
        job = event.payload[:job]
        return unless job

        failures = handled_job_failures
        failures.clear if failures.length >= 256
        failures[job.object_id] = true
      end

      def record_mail(event)
        failed = event_failed?(event.payload)
        recorder.record(
          "mail.delivery.duration_ms",
          value: event.duration,
          dimensions: { outcome: failed ? "failure" : "success" },
          at: event_time(event)
        )
        return unless failed

        recorder.record("mail.failure", at: event_time(event))
      end

      def record_payment_webhook(event)
        recorder.record(
          "payments.webhook.processed",
          dimensions: {
            provider: event.payload[:provider],
            outcome: event.payload[:outcome]
          },
          at: event_time(event)
        )
      end

      def record_community_upload(event)
        upload_event = COMMUNITY_UPLOAD_EVENTS.fetch(event.name)
        recorder.record(
          "community.upload.event",
          dimensions: {
            event: upload_event,
            kind: event.payload[:kind]
          },
          at: event_time(event)
        )
      end

      def record_community_scan(event)
        scan_outcome = COMMUNITY_SCAN_EVENTS.fetch(event.name)
        recorder.record(
          "community.scan.event",
          dimensions: { outcome: scan_outcome },
          at: event_time(event)
        )
      end

      private

      def subscribe(name, handler)
        @subscribers << ActiveSupport::Notifications.subscribe(name) do |event|
          next if Operations::Metrics.silenced?

          public_send(:"record_#{handler}", event)
        rescue StandardError => error
          ::Operations::Metrics.report_failure("notification ignored", error)
        end
      end

      def request_surface(controller)
        value = controller.to_s
        return "admin" if value.start_with?("Admin::")
        return "api" if value.start_with?("Api::")
        return "app" if value.start_with?("App::")
        return "website" if value.start_with?("Website::")

        "other"
      end

      def normalized_queue(job)
        queue = job.respond_to?(:queue_name) ? job.queue_name.to_s : ""
        ::Operations::Metrics::Catalog::QUEUES.include?(queue) ? queue : "other"
      end

      def consume_handled_job_failure(job)
        return false unless job

        handled_job_failures.delete(job.object_id) == true
      end

      def handled_job_failures
        ActiveSupport::IsolatedExecutionState[HANDLED_JOB_FAILURES_KEY] ||= {}
      end

      def event_failed?(payload)
        payload[:exception_object].present? ||
          payload[:exception].present?
      end

      def event_time(_event)
        # ActiveSupport events use a monotonic clock for duration. Event#end is
        # therefore not a wall-clock timestamp and must never become a bucket
        # time.
        Time.current
      end

      def recorder
        @recorder.respond_to?(:call) ? @recorder.call : @recorder
      end

      def configured_slow_query_ms
        parsed = Integer(
          ENV.fetch(
            "MCWEB_SLOW_QUERY_WARNING_MS",
            DEFAULT_SLOW_QUERY_MS.to_s
          ),
          exception: false
        )
        return DEFAULT_SLOW_QUERY_MS unless parsed&.between?(
          MIN_SLOW_QUERY_MS,
          MAX_SLOW_QUERY_MS
        )

        parsed
      end
    end
  end
end
