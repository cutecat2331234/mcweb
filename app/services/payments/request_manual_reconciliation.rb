# frozen_string_literal: true

module Payments
  class RequestManualReconciliation < ApplicationService
    PROVIDER = "stripe"
    PERMISSION = "store.payments.reconciliation.run"
    AUDIT_ACTION = "admin.payment_reconciliation_requested"
    ENQUEUE_FAILURE_CODE = "manual_enqueue_failed"
    MAX_LOOKBACK_DAYS = 365
    DUPLICATE_REQUEST_WINDOW = Payments::ReconciliationRun::LEASE_TIMEOUT
    RATE_LIMIT_WINDOW = 15.minutes
    ACTOR_RATE_LIMIT = 3
    IP_RATE_LIMIT = 6
    GLOBAL_RATE_LIMIT = 20
    MAX_ACTIVE_RUNS = 3
    ISO_DATE_PATTERN = /\A\d{4}-\d{2}-\d{2}\z/

    class << self
      def date_bounds(at: Time.current)
        maximum = at.utc.to_date - 1.day
        minimum = maximum - (MAX_LOOKBACK_DAYS - 1)
        minimum..maximum
      end

      def confirmation_for(date)
        "RECONCILE #{date.to_date.iso8601} UTC"
      end

      def provider_ready?(config)
        !Payments::Provider.developer_mode_fake_only? &&
          config&.reconciliation_ready?
      end

      def normalize_date(value)
        text = value.to_s
        return unless text.match?(ISO_DATE_PATTERN)

        Date.iso8601(text).tap do |date|
          return unless date.iso8601 == text
        end
      rescue Date::Error, ArgumentError
        nil
      end
    end

    def initialize(
      actor:,
      date:,
      token:,
      confirmation:,
      clock: -> { Time.current },
      job_class: Payments::DailyReconciliationJob,
      ip_address: nil,
      user_agent: nil
    )
      @actor = actor
      @date_input = date
      @token = token
      @confirmation = confirmation.to_s.strip
      @clock = clock
      @job_class = job_class
      @ip_address = ip_address
      @user_agent = user_agent.to_s.first(500).presence
    end

    def call
      return forbidden_result unless @actor&.permission?(PERMISSION)

      date = normalized_date
      return invalid_date_result unless date
      return date_out_of_range_result unless self.class.date_bounds(at: now).cover?(date)
      return confirmation_mismatch_result unless confirmed?(date)
      rate_limit = enforce_request_limits
      return rate_limit if rate_limit.failure?

      reservation = reserve(date)
      return reservation if reservation.failure?
      return reservation unless reservation.value[:enqueued]

      enqueue(
        reservation.value.fetch(:run),
        date,
        reservation.value.fetch(:config_binding)
      )
    end

    private

    def reserve(date)
      result = nil

      Payments::ProviderConfig.transaction do
        config = Payments::ProviderConfig.lock.find_by(provider: PROVIDER)
        unless config && Payments::ManualReconciliationToken.valid?(
          @token,
          actor: @actor,
          config: config,
          date: date
        )
          result = invalid_token_result
          raise ActiveRecord::Rollback
        end
        unless self.class.provider_ready?(config)
          result = provider_not_ready_result
          raise ActiveRecord::Rollback
        end
        unless Payments::ManualReconciliationToken.consume?(
          @token,
          actor: @actor,
          config: config,
          date: date
        )
          result = invalid_token_result
          raise ActiveRecord::Rollback
        end

        run = find_or_create_run!(config: config, date: date)
        newly_created = run.previously_new_record?
        run.lock!
        disposition = duplicate_disposition(run) unless newly_created
        if disposition
          result = ServiceResult.success(
            run: run,
            enqueued: false,
            disposition: disposition
          )
          next
        end
        unless active_run_capacity_available?(excluding_id: run.id)
          result = rate_limited_result
          raise ActiveRecord::Rollback
        end

        run.update!(
          status: "pending",
          phase: "payments",
          processing_token: nil,
          last_heartbeat_at: nil,
          failure_code: nil,
          failed_at: nil,
          completed_at: nil
        )
        Administration::AuditLogger.call(
          actor: @actor,
          action: AUDIT_ACTION,
          resource: run,
          metadata: {
            provider: run.provider,
            mode: run.mode,
            reconciliation_date: date.iso8601
          },
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        result = ServiceResult.success(
          run: run,
          enqueued: true,
          disposition: "enqueued",
          config_binding: Payments::ReconciliationConfigBinding.generate(
            config: config,
            run: run
          )
        )
      end

      result
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.error(
        "Manual payment reconciliation reservation failed " \
          "(#{error.class.name})."
      )
      failure(
        "The reconciliation request could not be reserved.",
        "reservation_failed"
      )
    end

    def enqueue(run, date, config_binding)
      @job_class.perform_later(
        date: date.iso8601,
        refresh: false,
        run_id: run.id,
        config_binding: config_binding
      )
      ServiceResult.success(
        run: run,
        enqueued: true,
        disposition: "enqueued"
      )
    rescue StandardError => error
      mark_enqueue_failed(run)
      Rails.logger.error(
        "Manual payment reconciliation enqueue failed " \
          "(#{error.class.name}); run_id=#{run.id}."
      )
      failure(
        "The reconciliation request could not be queued.",
        "enqueue_failed"
      )
    end

    def mark_enqueue_failed(run)
      Payments::ReconciliationRun.transaction do
        current = Payments::ReconciliationRun.lock.find(run.id)
        next unless current.pending? && current.processing_token.blank?

        current.update!(
          status: "failed",
          failure_code: ENQUEUE_FAILURE_CODE,
          failed_at: now,
          last_heartbeat_at: now
        )
      end
    rescue ActiveRecord::ActiveRecordError
      nil
    end

    def find_or_create_run!(config:, date:)
      window_start = Time.utc(date.year, date.month, date.day)
      Payments::ReconciliationRun.create_or_find_by!(
        provider: PROVIDER,
        mode: config.effective_mode,
        window_start: window_start,
        window_end: window_start + 1.day
      ) do |run|
        run.status = "pending"
        run.phase = "payments"
      end
    end

    def duplicate_disposition(run)
      return "already_running" if run.lease_active?(at: now)
      if run.pending? && run.updated_at >= now - DUPLICATE_REQUEST_WINDOW
        return "already_queued"
      end
      return if run.failure_code == ENQUEUE_FAILURE_CODE
      return unless recent_request?(run)

      "recently_requested"
    end

    def recent_request?(run)
      AuditLog.by_action(AUDIT_ACTION)
        .where(
          resource_type: run.class.name,
          resource_id: run.id,
          created_at: (now - DUPLICATE_REQUEST_WINDOW)..
        )
        .exists?
    end

    def normalized_date
      self.class.normalize_date(@date_input)
    end

    def enforce_request_limits
      dimensions = [
        [ "actor:#{@actor.id}", ACTOR_RATE_LIMIT ],
        [ "ip:#{Digest::SHA256.hexdigest(@ip_address.to_s)}", IP_RATE_LIMIT ],
        [ "global", GLOBAL_RATE_LIMIT ]
      ]
      dimensions.each do |dimension, limit|
        result = Administration::RateLimiter.call(
          key: "payment_manual_reconciliation:#{dimension}",
          limit: limit,
          window: RATE_LIMIT_WINDOW,
          developer_mode_bypass: false
        )
        return rate_limited_result if result.failure?
      end

      ServiceResult.success
    end

    def active_run_capacity_available?(excluding_id:)
      cutoff = now - Payments::ReconciliationRun::LEASE_TIMEOUT
      pending = Payments::ReconciliationRun
        .where(status: "pending")
        .where("updated_at >= ?", cutoff)
      running = Payments::ReconciliationRun
        .where(status: "running")
        .where("last_heartbeat_at >= ?", cutoff)
      pending = pending.where.not(id: excluding_id)
      running = running.where.not(id: excluding_id)

      pending.count + running.count < MAX_ACTIVE_RUNS
    end

    def confirmed?(date)
      expected = self.class.confirmation_for(date)
      @confirmation.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(@confirmation, expected)
    end

    def now
      @clock.call
    end

    def forbidden_result
      failure(
        "You do not have permission to request payment reconciliation.",
        "forbidden"
      )
    end

    def invalid_date_result
      failure("Enter a valid ISO reconciliation date.", "invalid_date")
    end

    def date_out_of_range_result
      bounds = self.class.date_bounds(at: now)
      failure(
        "Choose a completed UTC date between #{bounds.begin.iso8601} and " \
          "#{bounds.end.iso8601}.",
        "date_out_of_range"
      )
    end

    def confirmation_mismatch_result
      failure(
        "Enter the exact reconciliation confirmation text.",
        "confirmation_mismatch"
      )
    end

    def invalid_token_result
      failure(
        "Reconciliation authorization expired or is invalid.",
        "invalid_reconciliation_token"
      )
    end

    def provider_not_ready_result
      failure(
        "Stripe reconciliation is not ready. Test the current provider " \
          "configuration first.",
        "provider_not_ready"
      )
    end

    def rate_limited_result
      failure(
        "Too many reconciliation requests are active. Try again later.",
        "rate_limited"
      )
    end

    def failure(message, code)
      ServiceResult.failure(error: message, code: code)
    end
  end
end
