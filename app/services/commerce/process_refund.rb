# frozen_string_literal: true

module Commerce
  class ProcessRefund < ApplicationService
    class RestorationFailure < StandardError; end

    DEFINITIVE_PROVIDER_FAILURE_CODES = %w[
      environment_mismatch
      provider_configuration_missing
      provider_payment_missing
    ].freeze
    DEFINITIVE_PROVIDER_FAILURE_STATUSES = %w[failed canceled cancelled].freeze

    def initialize(
      order:,
      payment_record:,
      amount_cents:,
      reason: nil,
      reason_kind: nil,
      requested_by: nil,
      approved_by: nil,
      existing_refund: nil
    )
      @order = order
      @payment_record = payment_record
      @amount_cents = amount_cents.to_i
      @reason = reason
      @reason_kind = reason_kind.to_s.presence
      @requested_by = requested_by
      @approved_by = approved_by
      @existing_refund = existing_refund
    end

    def call
      preparation = prepare_refund!
      return preparation if preparation.is_a?(ServiceResult)

      refund = preparation.fetch(:refund)
      return ServiceResult.success(refund) if preparation[:idempotent]

      if preparation[:provider_required]
        provider_result = provider_result_for(refund)
        provider_outcome = persist_provider_result!(refund, provider_result)
        if provider_outcome == :unknown
          return refund_failure(
            :refund_provider_outcome_unknown,
            value: { refund: refund.reload, provider_result: provider_result.value }
          )
        end
        return provider_result if provider_result.failure?
      end

      restoration = complete_local_restoration!(refund)
      return restoration if restoration.failure?
      return ServiceResult.success(restoration.value[:refund]) if restoration.value[:idempotent]

      success_refund = restoration.value.fetch(:refund)
      previous_status = restoration.value.fetch(:previous_status)
      deliver_refund_notifications!(success_refund, previous_status)
      Administration::AuditLogger.call(
        actor: @approved_by || @requested_by,
        action: "commerce.refund_processed",
        resource: success_refund,
        metadata: { amount_cents: success_refund.amount_cents }
      )

      ServiceResult.success(success_refund)
    rescue Commerce::FinancialLocking::BindingMismatch
      refund_failure(:refund_binding_mismatch)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def prepare_refund!
      refund = nil
      error = nil
      idempotent = false
      provider_required = true

      Commerce::Refund.transaction do
        lock_order_and_payment!

        unless refundable_payment?
          error = :payment_not_refundable
          raise ActiveRecord::Rollback
        end

        if @amount_cents <= 0
          error = :refund_amount_invalid
          raise ActiveRecord::Rollback
        end

        refund = lock_refund(find_or_build_refund)
        identity_error = validate_refund_identity(refund)
        if identity_error
          error = identity_error
          raise ActiveRecord::Rollback
        end

        if refund.persisted? && refund.amount_cents != @amount_cents
          error = refund.completed? ? :refund_completed_amount_immutable : :refund_amount_immutable
          raise ActiveRecord::Rollback
        end

        if refund.completed?
          idempotent = true
          next
        end

        if refund.provider_confirmed?
          unless local_restoration_claimable?(refund)
            error = :refund_restoration_in_progress
            raise ActiveRecord::Rollback
          end

          refund.update!(
            status: "approved",
            restoration_status: "processing",
            restoration_attempts: refund.restoration_attempts + 1,
            restoration_error: nil,
            processing_started_at: Time.current
          )
          provider_required = false
          next
        end

        if refund.approved? && !refund.processing_stale?
          error = :refund_processing_in_progress
          raise ActiveRecord::Rollback
        end

        unless refund.new_record? || refund.pending? || refund.failed? || refund.processing_stale?
          error = :refund_no_longer_valid
          raise ActiveRecord::Rollback
        end

        reserved_cents = @payment_record.refunds
          .reserved
          .where.not(id: refund.id)
          .sum(:amount_cents)
        remaining_cents = @payment_record.amount_cents - reserved_cents

        if @amount_cents > remaining_cents
          error = :refund_exceeds_balance
          raise ActiveRecord::Rollback
        end

        refund.assign_attributes(
          order: @order,
          payment_record: @payment_record,
          status: "approved",
          amount_cents: @amount_cents,
          reason: resolved_reason(refund),
          reason_kind: resolved_reason_kind(refund),
          approved_by: @approved_by || refund.approved_by,
          provider_error_code: nil,
          restoration_status: "pending",
          restoration_error: nil,
          processing_started_at: Time.current
        )
        refund.save!
      end

      return refund_failure(error) if error
      return refund_failure(:unable_to_prepare_refund) unless refund&.persisted?

      { refund: refund, idempotent: idempotent, provider_required: provider_required }
    end

    def persist_provider_result!(refund, provider_result)
      details = provider_result.value.is_a?(Hash) ? provider_result.value.symbolize_keys : {}
      persisted_outcome = nil

      Commerce::Refund.transaction do
        locked_refund = lock_order_payment_refund!(refund.id)

        attributes = {
          provider_refund_id: details[:provider_refund_id].presence || locked_refund.provider_refund_id,
          provider_status: details[:provider_status].presence || locked_refund.provider_status,
          provider_error_code: details[:provider_error_code].presence || provider_result.code,
          provider_metadata: locked_refund.provider_metadata.merge(
            details.fetch(:provider_metadata, {}).to_h.stringify_keys
          )
        }

        persisted_outcome = provider_outcome(provider_result, details)
        if persisted_outcome == :confirmed
          attributes.merge!(
            status: "approved",
            provider_confirmed_at: locked_refund.provider_confirmed_at || Time.current,
            provider_error_code: nil,
            restoration_status: "processing",
            restoration_attempts: locked_refund.restoration_attempts + 1,
            restoration_error: nil,
            processing_started_at: Time.current
          )
        elsif persisted_outcome == :pending
          attributes.merge!(
            status: "approved",
            restoration_status: "pending",
            processing_started_at: Time.current
          )
        elsif persisted_outcome == :failed
          attributes.merge!(
            status: "failed",
            restoration_status: "pending",
            processing_started_at: nil
          )
        else
          attributes.merge!(
            status: "provider_unknown",
            restoration_status: "pending",
            processing_started_at: locked_refund.processing_started_at || Time.current,
            provider_metadata: attributes.fetch(:provider_metadata).merge(
              "outcome_classification" => "unknown"
            )
          )
        end

        locked_refund.update!(attributes)
        next if provider_result.success?

        Commerce::OrderEvent.create!(
          order: @order,
          actor: @approved_by,
          event_type: provider_event_type(persisted_outcome),
          metadata: {
            refund_id: locked_refund.id,
            provider_status: locked_refund.provider_status,
            error_code: locked_refund.provider_error_code
          }.compact
        )
      end

      persisted_outcome
    end

    def complete_local_restoration!(refund)
      success_refund = nil
      previous_status = nil
      idempotent = false

      Commerce::Refund.transaction do
        locked_refund = lock_order_payment_refund!(refund.id)

        if locked_refund.completed?
          success_refund = locked_refund
          idempotent = true
          next
        end

        unless locked_refund.provider_confirmed?
          raise RestorationFailure, I18n.t("mcweb.services.errors.refund_provider_not_confirmed")
        end

        previous_status = @order.status
        progress = restoration_progress(locked_refund)
        apply_refund_restorations!(progress)

        locked_refund.update!(
          status: "completed",
          restoration_status: "completed",
          restoration_error: nil,
          restoration_completed_at: Time.current,
          processing_started_at: nil
        )
        Commerce::OrderEvent.create!(
          order: @order,
          actor: @approved_by || @requested_by,
          event_type: "refund_processed",
          metadata: {
            refund_id: locked_refund.id,
            amount_cents: locked_refund.amount_cents,
            restoration_amount_cents: progress.fetch(:refund_amount_cents)
          }
        )
        dispute_result = Commerce::Disputes::RebalanceExposure.call(
          payment_record: @payment_record,
          trigger_idempotency: "refund:#{locked_refund.id}:dispute-rebalance"
        )
        unless dispute_result.success?
          raise RestorationFailure,
            dispute_result.error.presence || I18n.t("mcweb.services.errors.refund_dispute_reconciliation_failed")
        end
        receipt_result = Commerce::IssueFinanceRefundReceipt.call(
          refund: locked_refund,
          actor: @approved_by || @requested_by
        )
        unless receipt_result.success?
          raise RestorationFailure,
            receipt_result.error.presence || I18n.t("mcweb.services.errors.refund_receipt_issue_failed")
        end
        payload = Commerce::DomainEvents.refund(locked_refund)
        Commerce::DomainEvents.publish_after_commit(
          "commerce.refund.processed",
          payload
        )
        Commerce::DomainEvents.publish_after_commit(
          "commerce.payment.refunded",
          payload
        )
        success_refund = locked_refund
      end

      ServiceResult.success(
        refund: success_refund,
        previous_status: previous_status,
        idempotent: idempotent
      )
    rescue RestorationFailure => e
      record_restoration_failure!(refund, e.message)
      ServiceResult.failure(
        error: e.message,
        code: "restoration_failed",
        value: { refund: refund.reload, retryable: true }
      )
    rescue ActiveRecord::ActiveRecordError => e
      handle_unexpected_restoration_failure(refund, e)
    rescue StandardError => e
      handle_unexpected_restoration_failure(refund, e)
    end

    def apply_refund_restorations!(progress)
      restore_arguments = {
        order: @order,
        refund_amount_cents: progress.fetch(:refund_amount_cents),
        payment_amount_cents: progress.fetch(:payment_amount_cents),
        already_refunded_cents: progress.fetch(:already_refunded_cents)
      }

      ensure_restored!(
        Commerce::RestoreStoreCreditPartial.call(**restore_arguments),
        I18n.t("mcweb.services.errors.store_credit_restore_failed")
      )
      ensure_restored!(
        Commerce::RestoreStockPartial.call(**restore_arguments),
        I18n.t("mcweb.services.errors.stock_restore_failed")
      )
      ensure_restored!(
        Commerce::RestoreCouponPartial.call(**restore_arguments),
        I18n.t("mcweb.services.errors.coupon_restore_failed")
      )
      ensure_restored!(
        Commerce::RestoreGiftCardPartial.call(**restore_arguments),
        I18n.t("mcweb.services.errors.gift_card_balance_restore_failed")
      )

      return unless progress.fetch(:full_refund)

      unless @order.may_refund?
        raise RestorationFailure, I18n.t("mcweb.services.errors.order_refund_status_failed")
      end

      @order.refund!
      ensure_restored!(
        Commerce::RevokeIssuedGiftCards.call(order: @order),
        I18n.t("mcweb.services.errors.gift_card_revoke_failed")
      )
      ensure_restored!(
        Commerce::RevokeMembershipsForOrder.call(order: @order),
        I18n.t("mcweb.services.errors.membership_revoke_failed")
      )
      ensure_restored!(
        Commerce::RevokeEntitlementsForOrder.call(order: @order),
        I18n.t("mcweb.services.errors.refund_entitlement_revoke_failed")
      )
    end

    def restoration_progress(refund)
      completed_before = @order.refunds
        .completed
        .where.not(id: refund.id)
        .sum(:amount_cents)
      completed_after = completed_before + refund.amount_cents
      succeeded_total = @order.payment_records.succeeded.sum(:amount_cents)
      intended_payment = @order.total_cents.to_i

      if intended_payment <= 0
        raise RestorationFailure, I18n.t("mcweb.services.errors.refund_no_payment_basis")
      end

      overpayment = [ succeeded_total - intended_payment, 0 ].max
      effective_before = (completed_before - overpayment).clamp(0, intended_payment)
      effective_after = (completed_after - overpayment).clamp(0, intended_payment)

      {
        already_refunded_cents: effective_before,
        refund_amount_cents: effective_after - effective_before,
        payment_amount_cents: intended_payment,
        full_refund: effective_after >= intended_payment
      }
    end

    def record_restoration_failure!(refund, error)
      Commerce::Refund.transaction do
        locked_refund = lock_order_payment_refund!(refund.id)
        next if locked_refund.completed?

        locked_refund.update!(
          status: "approved",
          restoration_status: "failed",
          restoration_error: error.to_s.first(2_000),
          processing_started_at: nil
        )
        Commerce::OrderEvent.create!(
          order: @order,
          actor: @approved_by || @requested_by,
          event_type: "refund_restoration_failed",
          metadata: {
            refund_id: locked_refund.id,
            attempt: locked_refund.restoration_attempts,
            error: error.to_s.first(500)
          }
        )
      end
    end

    def handle_unexpected_restoration_failure(refund, error)
      Rails.logger.error(
        "[ProcessRefund] local restoration failed " \
        "refund_id=#{refund.id} error=#{error.class}: #{error.message}"
      )
      message = I18n.t("mcweb.services.errors.refund_restoration_failed")
      record_restoration_failure!(refund, message)
      ServiceResult.failure(
        error: message,
        code: "restoration_failed",
        value: { refund: refund.reload, retryable: true }
      )
    end

    def deliver_refund_notifications!(refund, previous_status)
      refund_id = refund.id
      ActiveRecord.after_all_transactions_commit do
        MailDeliveryJob.perform_later(
          "Commerce::OrderMailer",
          "refund_processed",
          "deliver_now",
          args: [ refund_id ]
        )
      end
      Commerce::NotifyOrderEvent.call(
        user: @order.user,
        notification_type: "commerce.refund_processed",
        title: -> { I18n.t("mcweb.labels.notification_types.commerce.refund_processed") },
        body: lambda {
          [
            I18n.t("mcweb.mail.commerce.refund_processed.body", number: @order.order_number),
            I18n.t(
              "mcweb.mail.commerce.refund_processed.amount",
              amount: format_refund_amount(refund.amount_cents)
            )
          ].join(" ")
        },
        path: "/app/store/orders/#{@order.public_id}"
      )
      Commerce::DispatchOrderWebhook.call(
        order: @order,
        event_type: "order.refunded",
        from_status: previous_status,
        to_status: @order.status,
        extra: { refund_amount_cents: refund.amount_cents, refund_id: refund.id }
      )
    end

    def lock_order_and_payment!
      @order, @payment_record = Commerce::FinancialLocking.lock_order_payment!(
        order_id: @order.id,
        payment_record_id: @payment_record.id
      )
    end

    def lock_order_payment_refund!(refund_id)
      @order, @payment_record, refund = Commerce::FinancialLocking.lock_order_payment_refund!(
        order_id: @order.id,
        payment_record_id: @payment_record.id,
        refund_id: refund_id
      )
      refund
    end

    def refundable_payment?
      @payment_record.store_order_id == @order.id && @payment_record.succeeded?
    end

    def lock_refund(refund)
      return refund unless refund.persisted?

      Commerce::Refund.lock.find(refund.id)
    end

    def validate_refund_identity(refund)
      return unless refund.persisted?
      return if refund.store_order_id == @order.id &&
        refund.payment_record_id == @payment_record.id

      :refund_binding_mismatch
    end

    def ensure_refund_binding!(refund)
      return if validate_refund_identity(refund).nil?

      refund.errors.add(:base, I18n.t("mcweb.validation_errors.refund_binding_changed_while_processing"))
      raise ActiveRecord::RecordInvalid.new(refund)
    end

    def local_restoration_claimable?(refund)
      refund.restoration_failed? ||
        refund.processing_started_at.nil? ||
        refund.processing_stale?
    end

    def find_or_build_refund
      return @existing_refund if @existing_refund

      pending = @payment_record.refunds
        .where(store_order_id: @order.id)
        .pending
        .order(created_at: :asc)
        .first
      return pending if pending && @approved_by

      Commerce::Refund.new(
        order: @order,
        payment_record: @payment_record,
        status: "pending",
        requested_by: @requested_by
      )
    end

    def refund_failure(code, value: nil)
      ServiceResult.failure(error: code, code: code, value: value)
    end

    def stable_provider_result(result)
      return result if result.success? || result.code.present?

      ServiceResult.failure(
        error: result.error.presence || :refund_provider_outcome_unknown,
        code: :refund_provider_outcome_unknown,
        value: provider_failure_details(result)
      )
    end

    def provider_result_for(refund)
      provider = Payments::Provider.for(@payment_record.provider)
      stable_provider_result(provider.process_refund(refund))
    rescue Payments::Provider::UnknownProviderError => error
      Rails.logger.warn("[ProcessRefund] provider unavailable (#{error.class})")
      ServiceResult.failure(
        error: :refund_provider_unavailable,
        code: :refund_provider_unavailable,
        value: {
          provider_status: "unavailable",
          provider_error_code: "refund_provider_unavailable",
          provider_metadata: { "provider_attempted" => false }
        }
      )
    rescue StandardError => error
      Rails.logger.error(
        "[ProcessRefund] provider outcome unknown " \
        "refund_id=#{refund.id} error=#{error.class}"
      )
      ServiceResult.failure(
        error: :refund_provider_outcome_unknown,
        code: :refund_provider_exception,
        value: {
          provider_status: "unknown",
          provider_error_code: "refund_provider_exception",
          provider_metadata: {
            "provider_attempted" => true,
            "exception_class" => error.class.name
          }
        }
      )
    end

    def provider_failure_details(result)
      details = result.value.is_a?(Hash) ? result.value.deep_symbolize_keys : {}
      metadata = details.fetch(:provider_metadata, {}).to_h.stringify_keys
      reported_error = result.error.to_s
      if reported_error.match?(/\A[a-z0-9_.-]{1,120}\z/)
        metadata["reported_error"] = reported_error
      end
      details.merge(provider_metadata: metadata)
    end

    def provider_outcome(provider_result, details)
      return :confirmed if provider_result.success?
      return :pending if provider_result.code.to_s == "provider_pending"
      return :failed if definitive_provider_failure?(provider_result, details)

      :unknown
    end

    def definitive_provider_failure?(provider_result, details)
      status = details[:provider_status].to_s
      return true if DEFINITIVE_PROVIDER_FAILURE_STATUSES.include?(status)
      return true if DEFINITIVE_PROVIDER_FAILURE_CODES.include?(provider_result.code.to_s)

      details.fetch(:provider_metadata, {}).to_h["provider_attempted"] == false
    end

    def provider_event_type(outcome)
      case outcome
      when :pending then "refund_provider_pending"
      when :unknown then "refund_provider_unknown"
      else "refund_failed"
      end
    end

    def resolved_reason(refund)
      return @reason if @reason.present?
      return nil if @reason_kind.present?

      refund.reason
    end

    def resolved_reason_kind(refund)
      return @reason_kind if @reason_kind.present?
      return nil if @reason.present?

      refund.reason_kind
    end

    def format_refund_amount(cents)
      ApplicationController.helpers.format_currency_from_cents(cents, @order.currency)
    end

    def ensure_restored!(result, fallback_message)
      return if result.success?

      raise RestorationFailure, result.error.presence || fallback_message
    end
  end
end
