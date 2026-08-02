# frozen_string_literal: true

module Commerce
  class ProcessRefund < ApplicationService
    class RestorationFailure < StandardError; end

    def initialize(
      order:,
      payment_record:,
      amount_cents:,
      reason: nil,
      requested_by: nil,
      approved_by: nil,
      existing_refund: nil
    )
      @order = order
      @payment_record = payment_record
      @amount_cents = amount_cents.to_i
      @reason = reason
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
        provider = Payments::Provider.for(@payment_record.provider)
        provider_result = provider.process_refund(refund)
        persist_provider_result!(refund, provider_result)
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
    rescue Payments::Provider::UnknownProviderError => e
      ServiceResult.failure(error: e.message)
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
          error = "Payment is not refundable."
          raise ActiveRecord::Rollback
        end

        if @amount_cents <= 0
          error = "Refund amount must be greater than zero."
          raise ActiveRecord::Rollback
        end

        refund = lock_refund(find_or_build_refund)
        identity_error = validate_refund_identity(refund)
        if identity_error
          error = identity_error
          raise ActiveRecord::Rollback
        end

        if refund.persisted? && refund.amount_cents != @amount_cents
          error = refund.completed? ?
            "Completed refund amount cannot be changed." :
            "Refund amount cannot be changed after creation."
          raise ActiveRecord::Rollback
        end

        if refund.completed?
          idempotent = true
          next
        end

        if refund.provider_confirmed?
          unless local_restoration_claimable?(refund)
            error = "Refund restoration is already being processed."
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
          error = "Refund is already being processed."
          raise ActiveRecord::Rollback
        end

        unless refund.new_record? || refund.pending? || refund.failed? || refund.processing_stale?
          error = "Refund is no longer valid."
          raise ActiveRecord::Rollback
        end

        reserved_cents = @payment_record.refunds
          .reserved
          .where.not(id: refund.id)
          .sum(:amount_cents)
        remaining_cents = @payment_record.amount_cents - reserved_cents

        if @amount_cents > remaining_cents
          error = "Refund amount exceeds remaining balance."
          raise ActiveRecord::Rollback
        end

        refund.assign_attributes(
          order: @order,
          payment_record: @payment_record,
          status: "approved",
          amount_cents: @amount_cents,
          reason: @reason.presence || refund.reason,
          approved_by: @approved_by || refund.approved_by,
          provider_error_code: nil,
          restoration_status: "pending",
          restoration_error: nil,
          processing_started_at: Time.current
        )
        refund.save!
      end

      return ServiceResult.failure(error: error) if error
      return ServiceResult.failure(error: :unable_to_prepare_refund) unless refund&.persisted?

      { refund: refund, idempotent: idempotent, provider_required: provider_required }
    end

    def persist_provider_result!(refund, provider_result)
      details = provider_result.value.is_a?(Hash) ? provider_result.value.symbolize_keys : {}

      Commerce::Refund.transaction do
        lock_order_and_payment!
        locked_refund = Commerce::Refund.lock.find(refund.id)
        ensure_refund_binding!(locked_refund)

        attributes = {
          provider_refund_id: details[:provider_refund_id].presence || locked_refund.provider_refund_id,
          provider_status: details[:provider_status].presence || locked_refund.provider_status,
          provider_error_code: details[:provider_error_code].presence || provider_result.code,
          provider_metadata: locked_refund.provider_metadata.merge(
            details.fetch(:provider_metadata, {}).to_h.stringify_keys
          )
        }

        if provider_result.success?
          attributes.merge!(
            status: "approved",
            provider_confirmed_at: locked_refund.provider_confirmed_at || Time.current,
            provider_error_code: nil,
            restoration_status: "processing",
            restoration_attempts: locked_refund.restoration_attempts + 1,
            restoration_error: nil,
            processing_started_at: Time.current
          )
        elsif provider_result.code == "provider_pending"
          attributes.merge!(
            status: "approved",
            restoration_status: "pending",
            processing_started_at: Time.current
          )
        else
          attributes.merge!(
            status: "failed",
            restoration_status: "pending",
            processing_started_at: nil
          )
        end

        locked_refund.update!(attributes)
        next if provider_result.success?

        Commerce::OrderEvent.create!(
          order: @order,
          actor: @approved_by,
          event_type: provider_result.code == "provider_pending" ? "refund_provider_pending" : "refund_failed",
          metadata: {
            refund_id: locked_refund.id,
            provider_status: locked_refund.provider_status,
            error_code: locked_refund.provider_error_code
          }.compact
        )
      end
    end

    def complete_local_restoration!(refund)
      success_refund = nil
      previous_status = nil
      idempotent = false

      Commerce::Refund.transaction do
        lock_order_and_payment!
        locked_refund = Commerce::Refund.lock.find(refund.id)
        ensure_refund_binding!(locked_refund)

        if locked_refund.completed?
          success_refund = locked_refund
          idempotent = true
          next
        end

        unless locked_refund.provider_confirmed?
          raise RestorationFailure, "Refund provider result has not been confirmed."
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
            dispute_result.error.presence || "Dispute exposure could not be reconciled."
        end
        receipt_result = Commerce::IssueFinanceRefundReceipt.call(
          refund: locked_refund,
          actor: @approved_by || @requested_by
        )
        unless receipt_result.success?
          raise RestorationFailure,
            receipt_result.error.presence || "Refund receipt could not be issued."
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
        "Digital entitlement revocation failed."
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
        raise RestorationFailure, "Order has no refundable payment basis."
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
        lock_order_and_payment!
        locked_refund = Commerce::Refund.lock.find(refund.id)
        ensure_refund_binding!(locked_refund)
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
      message = "Local refund restoration failed (#{error.class})."
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
      @order = Commerce::Order.lock.find(@order.id)
      @payment_record = Payments::Record.lock.find(@payment_record.id)
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

      "Refund does not belong to this order and payment."
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

    def format_refund_amount(cents)
      ApplicationController.helpers.format_currency_from_cents(cents, @order.currency)
    end

    def ensure_restored!(result, fallback_message)
      return if result.success?

      raise RestorationFailure, result.error.presence || fallback_message
    end
  end
end
