# frozen_string_literal: true

module Commerce
  class CompleteOrderPayment < ApplicationService
    FULFILL_ORDER_ENQUEUED_EVENT = "fulfill_order_enqueued"
    PLUGIN_ORDER_PAID_PUBLISHED_EVENT = "plugin_order_paid_published"

    def initialize(order:, from_status: nil, staff_marked: false)
      @order = order
      @from_status = from_status
      @staff_marked = staff_marked
    end

    def call
      unless post_payment_eligible?
        return ServiceResult.failure(error: "order_payment_not_completed")
      end

      ensure_staff_payment_record! if @staff_marked

      gift_result = Commerce::DebitGiftCard.call(order: @order)
      return gift_result unless gift_result.success?

      credit_result = Commerce::DebitStoreCredit.call(order: @order)
      return credit_result unless credit_result.success?

      invoice_result = Commerce::IssueFinanceInvoice.call(
        order: @order,
        payment_record: @order.primary_succeeded_payment_record
      )
      return invoice_result unless invoice_result.success?

      idempotent = true

      unless @order.post_payment_side_effects_completed?
        Commerce::PostPaymentSideEffectsJob.perform_later(@order.id)
        idempotent = false
      end

      unless skip_fulfillment_enqueue?
        enqueue_fulfillment_job!
        idempotent = false
      end

      publish_plugin_order_paid_after_commit!
      ServiceResult.success(idempotent: idempotent)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def post_payment_eligible?
      %w[paid processing fulfilling fulfilled completed].include?(@order.status)
    end

    def fulfillment_started?
      @order.processing? || @order.fulfilling? || @order.fulfilled? || @order.completed?
    end

    def skip_fulfillment_enqueue?
      fulfillment_started? ||
        @order.fulfillments.exists? ||
        @order.events.exists?(event_type: FULFILL_ORDER_ENQUEUED_EVENT)
    end

    def enqueue_fulfillment_job!
      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@order.id)
        next if order.events.exists?(event_type: FULFILL_ORDER_ENQUEUED_EVENT)

        order.events.create!(event_type: FULFILL_ORDER_ENQUEUED_EVENT, metadata: {})
        Commerce::FulfillOrderJob.perform_later(order.id)
      end
    end

    def ensure_staff_payment_record!
      return if @order.payment_records.where(status: "succeeded").exists?

      payment_record = Payments::Record.create!(
        order: @order,
        provider: "fake",
        amount_cents: @order.total_cents,
        currency: @order.currency,
        status: :succeeded,
        provider_payment_id: "staff-#{@order.public_id}",
        metadata: { staff_marked: true }
      )
      Commerce::DomainEvents.publish_after_commit(
        "commerce.payment.confirmed",
        Commerce::DomainEvents.payment(payment_record)
      )
    end

    def publish_plugin_order_paid_after_commit!
      payload = nil
      Commerce::Order.transaction do
        order = Commerce::Order.lock.find(@order.id)
        next if order.events.exists?(event_type: PLUGIN_ORDER_PAID_PUBLISHED_EVENT)

        order.events.create!(
          event_type: PLUGIN_ORDER_PAID_PUBLISHED_EVENT,
          metadata: { schema_version: "1" }
        )
        payload = Commerce::DomainEvents.order_paid(order)
      end
      return unless payload

      Commerce::DomainEvents.publish_after_commit("commerce.order.paid", payload)
    end
  end
end
