# frozen_string_literal: true

module Payments
  class ReconcileDay < ApplicationService
    PROVIDER = "stripe"
    PAGE_LEASE_ERROR = "reconciliation_lease_lost"
    LOCAL_SETTLEMENT_GRACE = 36.hours
    ADJACENT_WINDOW_TOLERANCE = 1.day
    PAID_ORDER_STATUSES = %w[
      paid processing fulfilling fulfilled completed refunded
    ].freeze
    PAYMENT_STATUS_MAP = {
      "succeeded" => %w[succeeded],
      "canceled" => %w[failed cancelled],
      "processing" => %w[pending processing],
      "requires_action" => %w[pending processing],
      "requires_capture" => %w[pending processing],
      "requires_confirmation" => %w[pending processing],
      "requires_payment_method" => %w[pending processing failed]
    }.freeze
    REFUND_STATUS_MAP = {
      "succeeded" => %w[completed],
      "failed" => %w[failed rejected],
      "canceled" => %w[failed rejected],
      "pending" => %w[pending approved],
      "requires_action" => %w[pending approved]
    }.freeze
    SAFE_FAILURE_CODES = %w[
      authentication_failed
      permission_denied
      rate_limited
      provider_unavailable
      provider_error
      invalid_provider_response
      environment_mismatch
      provider_configuration_changed
      reconciliation_lease_lost
      reconciliation_internal_error
    ].freeze

    def initialize(
      date: Date.yesterday,
      adapter: nil,
      refresh: false,
      clock: -> { Time.current },
      reserved_run_id: nil,
      expected_config_binding: nil
    )
      @date_input = date
      @adapter = adapter
      @refresh = refresh
      @clock = clock
      @reserved_run_id = reserved_run_id
      @expected_config_binding = expected_config_binding
      @run = nil
      @processing_token = nil
    end

    def call
      date = normalized_date
      return invalid_date_result unless date

      window_start = Time.utc(date.year, date.month, date.day)
      window_end = window_start + 1.day
      if reserved_request?
        snapshot = reserved_config_snapshot(
          window_start: window_start,
          window_end: window_end
        )
        return snapshot if snapshot.is_a?(ServiceResult)

        config = snapshot.fetch(:config)
        mode = @run.mode
        secret_key = snapshot.fetch(:secret_key)
      else
        config = Payments::ProviderConfig.for_provider(PROVIDER)
        mode = config&.effective_mode.to_s
          .presence_in(Payments::ReconciliationRun::MODES) || "test"
        @run = find_or_create_run!(
          mode: mode,
          window_start: window_start,
          window_end: window_end
        )
        secret_key = config&.credentials_hash&.stringify_keys&.fetch(
          "secret_key",
          nil
        )
      end

      unless provider_ready?(config)
        if reserved_request?
          return fail_reserved_configuration!
        else
          mark_skipped!
          return ServiceResult.success(run: @run.reload, skipped: true)
        end
      end

      claim = claim_lease!
      return ServiceResult.success(run: @run.reload, already_completed: true) if claim == :completed
      return ServiceResult.success(run: @run.reload, already_running: true) if claim == :running

      @adapter ||= Payments::StripeReconciliationAdapter.new(
        secret_key: secret_key,
        expected_mode: mode
      )

      loop do
        @run.reload
        case @run.phase
        when "payments"
          result = process_remote_phase!(
            subject_type: "payment",
            cursor_attribute: :payment_cursor,
            next_phase: "refunds"
          )
        when "refunds"
          result = process_remote_phase!(
            subject_type: "refund",
            cursor_attribute: :refund_cursor,
            next_phase: "local_checks"
          )
        when "local_checks"
          result = process_local_checks!
        when "completed"
          return ServiceResult.success(run: @run)
        else
          result = failure_result("invalid_provider_response")
        end

        return result if result.failure?
        return result if result.value.is_a?(Hash) && result.value[:lost_lease]
      end
    rescue ActiveRecord::ActiveRecordError => error
      fail_safely!("reconciliation_internal_error", error)
    rescue StandardError => error
      fail_safely!("reconciliation_internal_error", error)
    end

    private

    def normalized_date
      case @date_input
      when Date
        @date_input
      when Time, ActiveSupport::TimeWithZone
        @date_input.to_date
      else
        Date.iso8601(@date_input.to_s)
      end
    rescue Date::Error, ArgumentError
      nil
    end

    def find_or_create_run!(mode:, window_start:, window_end:)
      Payments::ReconciliationRun.create_or_find_by!(
        provider: PROVIDER,
        mode: mode,
        window_start: window_start,
        window_end: window_end
      ) do |run|
        run.status = "pending"
        run.phase = "payments"
      end
    end

    def reserved_request?
      @reserved_run_id.present? || @expected_config_binding.present?
    end

    def reserved_config_snapshot(window_start:, window_end:)
      @run = Payments::ReconciliationRun.find_by(id: @reserved_run_id)
      return failure_result("provider_configuration_changed") unless
        reserved_run_matches?(@run, window_start: window_start, window_end: window_end)
      if @run.completed? && !@refresh
        return ServiceResult.success(run: @run, already_completed: true)
      end
      if @run.lease_active?(at: now)
        return ServiceResult.success(run: @run, already_running: true)
      end

      snapshot = nil
      Payments::ProviderConfig.transaction do
        config = Payments::ProviderConfig.lock.find_by(provider: PROVIDER)
        unless config &&
            provider_ready?(config) &&
            Payments::ReconciliationConfigBinding.valid?(
              @expected_config_binding,
              config: config,
              run: @run
            )
          next
        end

        snapshot = {
          config: config,
          secret_key: config.credentials_hash.stringify_keys.fetch("secret_key")
        }
      end
      return snapshot if snapshot

      fail_reserved_configuration!
    end

    def reserved_run_matches?(run, window_start:, window_end:)
      run &&
        run.provider == PROVIDER &&
        run.mode.in?(Payments::ReconciliationRun::MODES) &&
        run.window_start == window_start &&
        run.window_end == window_end
    end

    def fail_reserved_configuration!
      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find_by(id: @run&.id)
        next unless run
        next if run.completed? || run.lease_active?(at: now)

        run.update!(
          status: "failed",
          processing_token: nil,
          failure_code: "provider_configuration_changed",
          failed_at: now,
          last_heartbeat_at: now
        )
        @run = run
      end
      failure_result("provider_configuration_changed")
    end

    def provider_ready?(config)
      return false if Payments::Provider.developer_mode_fake_only?

      config&.reconciliation_ready?
    end

    def mark_skipped!
      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        next if run.completed? || run.lease_active?(at: now)

        run.update!(
          status: "skipped",
          phase: "completed",
          failure_code: "provider_not_configured",
          processing_token: nil,
          last_heartbeat_at: now,
          completed_at: now,
          failed_at: nil
        )
      end
    end

    def claim_lease!
      state = nil

      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        if run.completed? && !@refresh
          state = :completed
          next
        end
        if run.lease_active?(at: now)
          state = :running
          next
        end

        starting_refresh = run.pending? || run.completed? || run.skipped?
        if starting_refresh
          run.observations.delete_all
          run.assign_attributes(
            phase: "payments",
            payment_cursor: nil,
            refund_cursor: nil,
            payments_checked: 0,
            refunds_checked: 0,
            completed_at: nil,
            refresh_count: run.refresh_count + 1,
            refresh_started_at: now
          )
        elsif run.refresh_started_at.nil?
          run.assign_attributes(
            refresh_count: run.refresh_count + 1,
            refresh_started_at: now
          )
        end

        @processing_token = SecureRandom.hex(24)
        run.update!(
          status: "running",
          processing_token: @processing_token,
          attempt_count: run.attempt_count + 1,
          started_at: run.started_at || now,
          last_heartbeat_at: now,
          failed_at: nil,
          failure_code: nil
        )
        @run = run
        state = :claimed
      end

      state
    end

    def process_remote_phase!(subject_type:, cursor_attribute:, next_phase:)
      loop do
        @run.reload
        cursor = @run.public_send(cursor_attribute)
        page =
          if subject_type == "payment"
            @adapter.payment_page(
              window_start: @run.window_start,
              window_end: @run.window_end,
              cursor: cursor
            )
          else
            @adapter.refund_page(
              window_start: @run.window_start,
              window_end: @run.window_end,
              cursor: cursor
            )
          end

        if page.failure?
          fail_run!(page.code)
          return page
        end

        items = Array(page.value[:items])
        next_cursor = page.value[:next_cursor].presence
        committed = commit_remote_page!(
          subject_type: subject_type,
          items: items,
          cursor_attribute: cursor_attribute,
          next_cursor: next_cursor,
          next_phase: next_phase
        )
        return lost_lease_result unless committed
        return ServiceResult.success(run: @run.reload) unless next_cursor
      end
    end

    def commit_remote_page!(subject_type:, items:, cursor_attribute:, next_cursor:, next_phase:)
      committed = false

      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        unless lease_owned?(run)
          next
        end

        items.each do |item|
          if subject_type == "payment"
            process_payment_item!(run, item.symbolize_keys)
          else
            process_refund_item!(run, item.symbolize_keys)
          end
        end

        attributes = {
          last_heartbeat_at: now,
          payments_checked: run.observations.where(subject_type: "payment").count,
          refunds_checked: run.observations.where(subject_type: "refund").count,
          discrepancies_count: run.discrepancies.count
        }
        if next_cursor
          attributes[cursor_attribute] = next_cursor
        else
          attributes[cursor_attribute] = nil
          attributes[:phase] = next_phase
        end
        run.update!(attributes)
        @run = run
        committed = true
      end

      committed
    end

    def process_payment_item!(run, item)
      reference = item.fetch(:reference)
      digest = reference_digest(reference)
      observe!(run, "payment", digest)
      match = locate_payment(item)
      if match[:metadata_mismatch]
        record_discrepancy!(
          run,
          subject_type: "payment",
          kind: "payment_metadata_mismatch",
          reference: reference,
          reference_digest: digest,
          provider_status: item[:status],
          provider_amount_cents: item[:amount_cents],
          provider_currency: item[:currency]
        )
        return
      end
      payment = match[:record]

      unless payment
        record_discrepancy!(
          run,
          subject_type: "payment",
          kind: "provider_payment_missing_local",
          reference: reference,
          reference_digest: digest,
          provider_status: item[:status],
          provider_amount_cents: item[:amount_cents],
          provider_currency: item[:currency]
        )
        return
      end

      common = {
        reference: reference,
        reference_digest: digest,
        payment_record: payment,
        order: payment.order,
        local_status: payment.status,
        provider_status: item[:status],
        local_amount_cents: payment.amount_cents,
        provider_amount_cents: item[:amount_cents],
        local_currency: normalized_currency(payment.currency),
        provider_currency: item[:currency]
      }
      if match[:reference_missing]
        record_discrepancy!(
          run,
          **common,
          subject_type: "payment",
          kind: "payment_reference_missing"
        )
      end
      if payment.amount_cents != item[:amount_cents]
        record_discrepancy!(run, **common, subject_type: "payment", kind: "payment_amount_mismatch")
      end
      unless normalized_currency(payment.currency) == item[:currency]
        record_discrepancy!(run, **common, subject_type: "payment", kind: "payment_currency_mismatch")
      end

      expected_statuses = PAYMENT_STATUS_MAP[item[:status]]
      if expected_statuses.nil? || !payment.status.in?(expected_statuses)
        record_discrepancy!(run, **common, subject_type: "payment", kind: "payment_status_mismatch")
      end
      if payment.order.total_cents != item[:amount_cents]
        record_discrepancy!(
          run,
          **common.merge(
            local_amount_cents: payment.order.total_cents,
            local_currency: normalized_currency(payment.order.currency)
          ),
          subject_type: "payment",
          kind: "order_amount_mismatch"
        )
      end
      unless normalized_currency(payment.order.currency) == item[:currency]
        record_discrepancy!(
          run,
          **common.merge(
            local_amount_cents: payment.order.total_cents,
            local_currency: normalized_currency(payment.order.currency)
          ),
          subject_type: "payment",
          kind: "order_currency_mismatch"
        )
      end
      if item[:status] == "succeeded" && !payment.order.status.in?(PAID_ORDER_STATUSES)
        record_discrepancy!(run, **common, subject_type: "payment", kind: "order_status_mismatch")
      end
    end

    def process_refund_item!(run, item)
      reference = item.fetch(:reference)
      digest = reference_digest(reference)
      observe!(run, "refund", digest)
      match = locate_refund(item)
      if match[:metadata_mismatch]
        record_discrepancy!(
          run,
          subject_type: "refund",
          kind: "refund_metadata_mismatch",
          reference: reference,
          reference_digest: digest,
          provider_status: item[:status],
          provider_amount_cents: item[:amount_cents],
          provider_currency: item[:currency]
        )
        return
      end
      refund = match[:record]

      unless refund
        record_discrepancy!(
          run,
          subject_type: "refund",
          kind: "provider_refund_missing_local",
          reference: reference,
          reference_digest: digest,
          provider_status: item[:status],
          provider_amount_cents: item[:amount_cents],
          provider_currency: item[:currency]
        )
        return
      end

      payment = refund.payment_record
      common = {
        reference: reference,
        reference_digest: digest,
        payment_record: payment,
        refund: refund,
        order: refund.order,
        local_status: refund.status,
        provider_status: item[:status],
        local_amount_cents: refund.amount_cents,
        provider_amount_cents: item[:amount_cents],
        local_currency: normalized_currency(payment.currency),
        provider_currency: item[:currency]
      }
      if match[:reference_missing]
        record_discrepancy!(
          run,
          **common,
          subject_type: "refund",
          kind: "refund_reference_missing"
        )
      end
      if refund.amount_cents != item[:amount_cents]
        record_discrepancy!(run, **common, subject_type: "refund", kind: "refund_amount_mismatch")
      end
      unless normalized_currency(payment.currency) == item[:currency]
        record_discrepancy!(run, **common, subject_type: "refund", kind: "refund_currency_mismatch")
      end
      local_payment_reference = payment_reference(payment)
      unless local_payment_reference.present? &&
          secure_match?(local_payment_reference, item[:payment_reference])
        record_discrepancy!(
          run,
          **common,
          subject_type: "refund",
          kind: "refund_payment_mismatch"
        )
      end

      expected_statuses = REFUND_STATUS_MAP[item[:status]]
      if expected_statuses.nil? || !refund.status.in?(expected_statuses)
        record_discrepancy!(run, **common, subject_type: "refund", kind: "refund_status_mismatch")
      end
    end

    def process_local_checks!
      return lost_lease_result unless process_unknown_local_payment_batches!
      return lost_lease_result unless process_unknown_local_refund_batches!
      return lost_lease_result unless process_local_payment_batches!
      return lost_lease_result unless process_local_refund_batches!

      completed = false
      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        unless lease_owned?(run)
          next
        end

        resolve_absent_discrepancies!(run)
        run.update!(
          status: "completed",
          phase: "completed",
          processing_token: nil,
          failure_code: nil,
          failed_at: nil,
          completed_at: now,
          last_heartbeat_at: now,
          payments_checked: run.observations.where(subject_type: "payment").count,
          refunds_checked: run.observations.where(subject_type: "refund").count,
          discrepancies_count: run.discrepancies.count
        )
        @run = run
        completed = true
      end

      completed ? ServiceResult.success(run: @run) : lost_lease_result
    end

    def process_local_payment_batches!
      local_payment_scope.in_batches(of: 100) do |batch|
        ids = batch.pluck(:id)
        committed = with_owned_run do |run|
          Payments::Record.includes(:order).where(id: ids).find_each do |payment|
            process_local_payment!(run, payment)
          end
        end
        return false unless committed
      end

      true
    end

    def process_unknown_local_payment_batches!
      unknown_local_payment_scope.in_batches(of: 100) do |batch|
        ids = batch.pluck(:id)
        committed = with_owned_run do |run|
          Payments::Record.includes(:order).where(id: ids).find_each do |payment|
            process_unknown_local_payment!(run, payment)
          end
        end
        return false unless committed
      end

      true
    end

    def process_local_refund_batches!
      local_refund_scope.in_batches(of: 100) do |batch|
        ids = batch.pluck(:id)
        committed = with_owned_run do |run|
          Commerce::Refund.includes(:order, :payment_record).where(id: ids).find_each do |refund|
            process_local_refund!(run, refund)
          end
        end
        return false unless committed
      end

      true
    end

    def process_unknown_local_refund_batches!
      unknown_local_refund_scope.in_batches(of: 100) do |batch|
        ids = batch.pluck(:id)
        committed = with_owned_run do |run|
          Commerce::Refund.includes(:order, :payment_record).where(id: ids).find_each do |refund|
            process_unknown_local_refund!(run, refund)
          end
        end
        return false unless committed
      end

      true
    end

    def with_owned_run
      committed = false
      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        unless lease_owned?(run)
          next
        end

        yield run
        run.update!(
          last_heartbeat_at: now,
          discrepancies_count: run.discrepancies.count
        )
        @run = run
        committed = true
      end
      committed
    end

    def process_local_payment!(run, payment)
      return unless actionable_local_payment?(payment)

      reference = payment_reference(payment)
      unless reference
        touched_this_refresh = run.refresh_started_at && run.discrepancies
          .where(
            kind: "payment_reference_missing",
            payment_record_id: payment.id,
            status: %w[open acknowledged ignored]
          )
          .where("last_seen_at >= ?", run.refresh_started_at)
          .exists?
        return if touched_this_refresh

        synthetic_digest = reference_digest("local-payment:#{payment.id}")
        record_discrepancy!(
          run,
          subject_type: "payment",
          kind: "payment_reference_missing",
          reference_digest: synthetic_digest,
          payment_record: payment,
          order: payment.order,
          local_status: payment.status,
          local_amount_cents: payment.amount_cents,
          local_currency: normalized_currency(payment.currency)
        )
        return
      end

      digest = reference_digest(reference)
      return if observed?(run, "payment", digest)

      record_discrepancy!(
        run,
        subject_type: "payment",
        kind: "local_payment_missing_provider",
        reference: reference,
        reference_digest: digest,
        payment_record: payment,
        order: payment.order,
        local_status: payment.status,
        local_amount_cents: payment.amount_cents,
        local_currency: normalized_currency(payment.currency)
      )
    end

    def process_unknown_local_payment!(run, payment)
      return unless actionable_local_payment?(payment)

      record_discrepancy!(
        run,
        subject_type: "payment",
        kind: "payment_environment_unknown",
        reference_digest: reference_digest("local-payment-mode:#{payment.id}"),
        payment_record: payment,
        order: payment.order,
        local_status: payment.status,
        local_amount_cents: payment.amount_cents,
        local_currency: normalized_currency(payment.currency)
      )
    end

    def process_local_refund!(run, refund)
      return unless actionable_local_refund?(refund)

      reference = refund.provider_refund_id.to_s.presence
      unless reference
        touched_this_refresh = run.refresh_started_at && run.discrepancies
          .where(
            kind: "refund_reference_missing",
            refund_id: refund.id,
            status: %w[open acknowledged ignored]
          )
          .where("last_seen_at >= ?", run.refresh_started_at)
          .exists?
        return if touched_this_refresh

        synthetic_digest = reference_digest("local-refund:#{refund.id}")
        record_discrepancy!(
          run,
          subject_type: "refund",
          kind: "refund_reference_missing",
          reference_digest: synthetic_digest,
          payment_record: refund.payment_record,
          refund: refund,
          order: refund.order,
          local_status: refund.status,
          local_amount_cents: refund.amount_cents,
          local_currency: normalized_currency(refund.payment_record.currency)
        )
        return
      end

      digest = reference_digest(reference)
      return if observed?(run, "refund", digest)

      record_discrepancy!(
        run,
        subject_type: "refund",
        kind: "local_refund_missing_provider",
        reference: reference,
        reference_digest: digest,
        payment_record: refund.payment_record,
        refund: refund,
        order: refund.order,
        local_status: refund.status,
        local_amount_cents: refund.amount_cents,
        local_currency: normalized_currency(refund.payment_record.currency)
      )
    end

    def process_unknown_local_refund!(run, refund)
      return unless actionable_local_refund?(refund)

      record_discrepancy!(
        run,
        subject_type: "refund",
        kind: "refund_environment_unknown",
        reference_digest: reference_digest("local-refund-mode:#{refund.id}"),
        payment_record: refund.payment_record,
        refund: refund,
        order: refund.order,
        local_status: refund.status,
        local_amount_cents: refund.amount_cents,
        local_currency: normalized_currency(refund.payment_record.currency)
      )
    end

    def local_payment_scope
      Payments::Record
        .where(provider: PROVIDER, provider_mode: @run.mode)
        .where(status: %w[succeeded processing])
        .where(created_at: @run.window_start...@run.window_end)
        .where("created_at <= ?", now - LOCAL_SETTLEMENT_GRACE)
        .order(:id)
    end

    def local_refund_scope
      Commerce::Refund
        .joins(:payment_record)
        .where(payment_records: { provider: PROVIDER, provider_mode: @run.mode })
        .where(status: %w[approved completed])
        .where(created_at: @run.window_start...@run.window_end)
        .where("store_refunds.created_at <= ?", now - LOCAL_SETTLEMENT_GRACE)
        .order(:id)
    end

    def unknown_local_payment_scope
      Payments::Record
        .where(provider: PROVIDER, provider_mode: nil)
        .where(status: %w[succeeded processing])
        .where(created_at: @run.window_start...@run.window_end)
        .where("created_at <= ?", now - LOCAL_SETTLEMENT_GRACE)
        .order(:id)
    end

    def unknown_local_refund_scope
      Commerce::Refund
        .joins(:payment_record)
        .where(payment_records: { provider: PROVIDER, provider_mode: nil })
        .where(status: %w[approved completed])
        .where(created_at: @run.window_start...@run.window_end)
        .where("store_refunds.created_at <= ?", now - LOCAL_SETTLEMENT_GRACE)
        .order(:id)
    end

    def locate_payment(item)
      return { record: nil, metadata_mismatch: true } if item[:metadata_valid] == false

      reference_matches = Payments::Record
        .where(provider: PROVIDER, provider_mode: @run.mode)
        .where(
          "provider_payment_id = :reference " \
            "OR metadata ->> 'stripe_payment_intent_id' = :reference",
          reference: item[:reference]
        )
        .limit(2)
        .to_a
      return { record: nil, metadata_mismatch: true } if reference_matches.many?

      reference_payment = reference_matches.first
      metadata_payment = nil
      if item[:local_payment_record_id]
        metadata_payment = Payments::Record.find_by(
          id: item[:local_payment_record_id],
          provider: PROVIDER,
          provider_mode: @run.mode
        )
        return { record: nil, metadata_mismatch: true } unless metadata_payment
      end

      if reference_payment
        if metadata_payment && metadata_payment.id != reference_payment.id
          return { record: nil, metadata_mismatch: true }
        end
        if item[:local_order_public_id] &&
            !secure_match?(reference_payment.order.public_id, item[:local_order_public_id])
          return { record: nil, metadata_mismatch: true }
        end

        return {
          record: reference_payment,
          metadata_mismatch: false,
          reference_missing: false
        }
      end

      if metadata_payment
        unless item[:local_order_public_id] &&
            secure_match?(metadata_payment.order.public_id, item[:local_order_public_id])
          return { record: nil, metadata_mismatch: true }
        end
        existing_reference = payment_reference(metadata_payment)
        if existing_reference.present? && !secure_match?(existing_reference, item[:reference])
          return { record: nil, metadata_mismatch: true }
        end

        return {
          record: metadata_payment,
          metadata_mismatch: false,
          reference_missing: true
        }
      end

      if item[:local_order_public_id] && !Commerce::Order.exists?(
        public_id: item[:local_order_public_id]
      )
        return { record: nil, metadata_mismatch: true }
      end

      { record: nil, metadata_mismatch: false, reference_missing: false }
    end

    def locate_refund(item)
      return { record: nil, metadata_mismatch: true } if item[:metadata_valid] == false

      reference_refund = Commerce::Refund.joins(:payment_record)
        .find_by(
          provider_refund_id: item[:reference],
          payment_records: { provider: PROVIDER, provider_mode: @run.mode }
        )
      metadata_refund = nil
      if item[:local_refund_id]
        metadata_refund = Commerce::Refund.joins(:payment_record)
          .find_by(
            id: item[:local_refund_id],
            payment_records: { provider: PROVIDER, provider_mode: @run.mode }
          )
        return { record: nil, metadata_mismatch: true } unless metadata_refund
      end

      if reference_refund
        if metadata_refund && metadata_refund.id != reference_refund.id
          return { record: nil, metadata_mismatch: true }
        end
        if item[:local_payment_record_id] &&
            reference_refund.payment_record_id != item[:local_payment_record_id]
          return { record: nil, metadata_mismatch: true }
        end
        if item[:local_order_public_id] &&
            !secure_match?(reference_refund.order.public_id, item[:local_order_public_id])
          return { record: nil, metadata_mismatch: true }
        end

        return {
          record: reference_refund,
          metadata_mismatch: false,
          reference_missing: false
        }
      end

      if metadata_refund
        unless item[:local_payment_record_id] &&
            metadata_refund.payment_record_id == item[:local_payment_record_id] &&
            item[:local_order_public_id] &&
            secure_match?(metadata_refund.order.public_id, item[:local_order_public_id]) &&
            metadata_refund.provider_refund_id.blank?
          return { record: nil, metadata_mismatch: true }
        end

        return {
          record: metadata_refund,
          metadata_mismatch: false,
          reference_missing: true
        }
      end

      { record: nil, metadata_mismatch: false, reference_missing: false }
    end

    def payment_reference(payment)
      metadata_reference = payment.metadata.to_h.stringify_keys["stripe_payment_intent_id"].to_s
      return metadata_reference if metadata_reference.match?(
        Payments::StripeReconciliationAdapter::PAYMENT_REFERENCE_PATTERN
      )

      provider_reference = payment.provider_payment_id.to_s
      if provider_reference.match?(Payments::StripeReconciliationAdapter::PAYMENT_REFERENCE_PATTERN)
        provider_reference
      end
    end

    def observe!(run, subject_type, digest)
      Payments::ReconciliationObservation.create_or_find_by!(
        run: run,
        subject_type: subject_type,
        reference_digest: digest
      )
    end

    def observed?(run, subject_type, digest)
      Payments::ReconciliationObservation
        .joins(:run)
        .where(subject_type: subject_type, reference_digest: digest)
        .where(
          payment_reconciliation_runs: {
            provider: run.provider,
            mode: run.mode
          }
        )
        .where(
          "(payment_reconciliation_observations.run_id = :run_id " \
            "OR payment_reconciliation_runs.status = 'completed')",
          run_id: run.id
        )
        .where(
          "payment_reconciliation_runs.window_start BETWEEN ? AND ?",
          run.window_start - ADJACENT_WINDOW_TOLERANCE,
          run.window_start + ADJACENT_WINDOW_TOLERANCE
        )
        .exists?
    end

    def record_discrepancy!(run, subject_type:, kind:, reference_digest:, reference: nil,
                            payment_record: nil, refund: nil, order: nil,
                            local_status: nil, provider_status: nil,
                            local_amount_cents: nil, provider_amount_cents: nil,
                            local_currency: nil, provider_currency: nil)
      normalized_local_status = safe_status(local_status)
      normalized_provider_status = safe_status(provider_status)
      normalized_local_currency = normalized_currency(local_currency)
      normalized_provider_currency = normalized_currency(provider_currency)
      fingerprint = Digest::SHA256.hexdigest(
        [
          run.id,
          subject_type,
          kind,
          reference_digest,
          payment_record&.id,
          refund&.id,
          order&.id,
          normalized_local_status,
          normalized_provider_status,
          local_amount_cents,
          provider_amount_cents,
          normalized_local_currency,
          normalized_provider_currency
        ].join("\0")
      )
      discrepancy = Payments::ReconciliationDiscrepancy.find_or_initialize_by(
        fingerprint: fingerprint
      )

      if discrepancy.new_record?
        discrepancy.assign_attributes(
          run: run,
          provider: run.provider,
          mode: run.mode,
          subject_type: subject_type,
          kind: kind,
          reference_masked: masked_reference(reference),
          reference_digest: reference_digest,
          payment_record: payment_record,
          refund: refund,
          order: order,
          local_status: normalized_local_status,
          provider_status: normalized_provider_status,
          local_amount_cents: local_amount_cents,
          provider_amount_cents: provider_amount_cents,
          local_currency: normalized_local_currency,
          provider_currency: normalized_provider_currency,
          first_seen_at: now,
          last_seen_at: now
        )
        discrepancy.save!
      else
        attributes = { last_seen_at: now }
        if discrepancy.resolved?
          attributes[:status] = "open"
          attributes[:resolved_at] = nil
        end
        discrepancy.update!(attributes)
      end

      discrepancy
    end

    def resolve_absent_discrepancies!(run)
      refresh_started_at = run.refresh_started_at
      return unless refresh_started_at

      run.discrepancies.open
        .where("last_seen_at < ?", refresh_started_at)
        .find_each do |discrepancy|
          discrepancy.update!(status: "resolved", resolved_at: now)
        end
    end

    def actionable_local_payment?(payment)
      payment.created_at <= now - LOCAL_SETTLEMENT_GRACE &&
        (payment.succeeded? || payment.processing?)
    end

    def actionable_local_refund?(refund)
      refund.created_at <= now - LOCAL_SETTLEMENT_GRACE &&
        (refund.approved? || refund.completed?)
    end

    def reference_digest(reference)
      Digest::SHA256.hexdigest("#{PROVIDER}\0#{@run.mode}\0#{reference}")
    end

    def masked_reference(reference)
      text = reference.to_s
      return if text.blank?

      prefix = text.include?("_") ? "#{text.split('_', 2).first}_" : ""
      "#{prefix}••••#{text.last(4)}"
    end

    def normalized_currency(value)
      text = value.to_s.upcase
      text if text.match?(/\A[A-Z]{3}\z/)
    end

    def safe_status(value)
      text = value.to_s
      text if text.match?(/\A[a-z_]{1,40}\z/)
    end

    def lease_owned?(run)
      run.running? &&
        run.processing_token.present? &&
        secure_match?(run.processing_token, @processing_token)
    end

    def secure_match?(left, right)
      left = left.to_s
      right = right.to_s
      left.bytesize == right.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(left, right)
    end

    def fail_run!(code)
      safe_code = code.to_s.presence_in(SAFE_FAILURE_CODES) || "provider_error"
      Payments::ReconciliationRun.transaction do
        run = Payments::ReconciliationRun.lock.find(@run.id)
        next unless lease_owned?(run)

        run.update!(
          status: "failed",
          processing_token: nil,
          failure_code: safe_code,
          failed_at: now,
          last_heartbeat_at: now
        )
        @run = run
      end
    end

    def fail_safely!(code, error)
      Rails.logger.error(
        "Payment reconciliation failed (#{error.class.name}); run_id=#{@run&.id || 'none'}"
      )
      fail_run!(code) if @run&.persisted? && @processing_token.present?
      failure_result(code)
    end

    def now
      @clock.call
    end

    def invalid_date_result
      ServiceResult.failure(
        error: "Enter a valid ISO reconciliation date.",
        code: "invalid_date"
      )
    end

    def failure_result(code)
      ServiceResult.failure(
        error: "Payment reconciliation could not be completed.",
        code: code
      )
    end

    def lost_lease_result
      ServiceResult.success(run: @run.reload, lost_lease: true, code: PAGE_LEASE_ERROR)
    end
  end
end
