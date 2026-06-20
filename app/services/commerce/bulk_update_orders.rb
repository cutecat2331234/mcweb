# frozen_string_literal: true



module Commerce

  class BulkUpdateOrders < ApplicationService

    ALLOWED_ACTIONS = %w[cancel_pending mark_fulfilled mark_paid].freeze



    def initialize(actor:, order_public_ids:, action:)

      @actor = actor

      @order_public_ids = Array(order_public_ids).map(&:to_s).uniq

      @action = action.to_s

    end



    def call

      return ServiceResult.failure(error: I18n.t("mcweb.services.errors.orders_not_selected")) if @order_public_ids.empty?

      return ServiceResult.failure(error: I18n.t("mcweb.services.errors.unsupported_bulk_action")) unless ALLOWED_ACTIONS.include?(@action)



      processed = 0

      failures = []



      Commerce::Order.where(public_id: @order_public_ids).find_each do |order|

        result = process_order(order)

        if result.success?

          processed += 1

        else

          failures << { id: order.public_id, error: result.error }

        end

      end



      ServiceResult.success(processed: processed, failed: failures.size, failures: failures)

    end



    private



    def process_order(order)

      case @action

      when "cancel_pending"

        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.order_cannot_cancel")) unless order.pending? || order.awaiting_payment?



        Commerce::CancelOrder.call(order: order, actor: @actor, reason: "staff_bulk")

      when "mark_fulfilled"

        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.order_cannot_mark_fulfilled")) unless order.may_mark_fulfilled?

        if automated_fulfillment_required?(order)

          return ServiceResult.failure(error: I18n.t("mcweb.services.errors.automated_fulfillment_required"))

        end



        previous_status = order.status

        order.mark_fulfilled!

        Commerce::NotifyOrderStatusChange.call(order: order, from_status: previous_status)

        ServiceResult.success

      when "mark_paid"

        if order.paid? || order.processing?

          return resume_incomplete_payment!(order) if incomplete_paid_order?(order)



          return ServiceResult.failure(error: I18n.t("mcweb.services.errors.order_cannot_mark_paid"))

        end



        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.order_cannot_mark_paid")) unless order.pending? || order.awaiting_payment?

        return ServiceResult.failure(error: I18n.t("mcweb.services.errors.order_payment_expired")) if order.payment_expired?



        from_status = nil

        mark_paid_error = nil



        Commerce::Order.transaction do

          order.lock!

          order.reload



          unless order.pending? || order.awaiting_payment?

            mark_paid_error = I18n.t("mcweb.services.errors.order_cannot_mark_paid")

            raise ActiveRecord::Rollback

          end



          from_status = order.status

          order.submit_payment! if order.pending? && order.may_submit_payment?

          unless order.awaiting_payment? && order.may_mark_paid?

            mark_paid_error = I18n.t("mcweb.services.errors.order_cannot_mark_paid")

            raise ActiveRecord::Rollback

          end



          gift_result = Commerce::DebitGiftCard.call(order: order)

          unless gift_result.success?

            mark_paid_error = gift_result.error

            raise ActiveRecord::Rollback

          end



          credit_result = Commerce::DebitStoreCredit.call(order: order)

          unless credit_result.success?

            mark_paid_error = credit_result.error

            raise ActiveRecord::Rollback

          end



          order.mark_paid!

          unless order.paid?

            mark_paid_error = I18n.t("mcweb.services.errors.order_mark_paid_failed")

            raise ActiveRecord::Rollback

          end

        end



        return ServiceResult.failure(error: mark_paid_error) if mark_paid_error.present?



        result = Commerce::CompleteOrderPayment.call(order: order, from_status: from_status, staff_marked: true)

        return result unless result.success?



        ServiceResult.success

      else

        ServiceResult.failure(error: I18n.t("mcweb.services.errors.unsupported_bulk_action"))

      end

    end



    def mc_connector_fulfillment?(order)

      order.items.any? do |item|

        snapshot = item.fulfillment_snapshot || {}

        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}

        server_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]

        commands = config["commands"] || config[:commands]

        server_id.present? || Array(commands).any?

      end

    end



    def automated_fulfillment_required?(order)

      mc_connector_fulfillment?(order) || gift_card_fulfillment?(order) || membership_fulfillment?(order)

    end



    def membership_fulfillment?(order)

      order.items.any? do |item|

        snapshot = item.fulfillment_snapshot || {}

        (snapshot["product_type"] || snapshot[:product_type]).to_s == "membership"

      end

    end



    def gift_card_fulfillment?(order)

      order.items.any? do |item|

        snapshot = item.fulfillment_snapshot || {}

        (snapshot["product_type"] || snapshot[:product_type]).to_s == "gift_card"

      end

    end



    def incomplete_paid_order?(order)

      return true if order.paid? && order.may_start_processing?

      return true if (order.paid? || order.processing?) && !order.post_payment_side_effects_completed?



      false

    end



    def resume_incomplete_payment!(order)

      result = Commerce::CompleteOrderPayment.call(order: order, from_status: order.status, staff_marked: true)

      return result unless result.success?



      ServiceResult.success

    end

  end

end


