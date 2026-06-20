# frozen_string_literal: true

module Admin
  module Store
    class OrdersController < BaseController
      before_action -> { require_permission("store.orders.read") }
      before_action :set_order, only: %i[show update staff_note]

      def index
        orders_scope = ::Commerce::Order.recent.includes(:user)
        if params[:q].present?
          q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          orders_scope = orders_scope.where("order_number ILIKE ?", q)
        end
        if params[:status].present?
          orders_scope = orders_scope.where(status: params[:status])
        end
        @pagy, orders = pagy(orders_scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.orders.title"),
          exportUrl: export_admin_store_orders_path(q: params[:q], status: params[:status]),
          statusTabs: order_status_tabs,
          columns: [
            admin_column(:order_number, t("mcweb.admin.store.orders.col_order_number"), link: true),
            admin_column(:customer, t("mcweb.admin.store.orders.col_customer")),
            admin_column(:status, t("mcweb.admin.store.orders.col_status")),
            admin_column(:total, t("mcweb.admin.store.orders.col_total"))
          ],
          rows: orders.map do |order|
            admin_row(
              order_number: order.order_number,
              customer: order.user.username,
              status: order_status_label(order.status),
              total: format_money(order.total_cents, order.currency),
              url: admin_store_order_path(order),
              publicId: order.public_id
            )
          end,
          pagination: pagy_props(@pagy),
          selectable: current_user.permission?("store.orders.refund"),
          bulkOrderUrl: current_user.permission?("store.orders.refund") ? bulk_update_admin_store_orders_path : nil,
          bulkOrderActions: bulk_order_actions
        }
      end

      def bulk_update
        require_bulk_update_permission!
        result = Commerce::BulkUpdateOrders.call(
          actor: current_user,
          order_public_ids: params[:order_ids],
          action: params[:action_type]
        )

        destination = safe_local_path(params[:return_to]) || admin_store_orders_path
        if result.success?
          notice = if result.value[:failed].positive?
                     t(
                       "mcweb.admin.store.orders.bulk_processed_with_failures",
                       processed: result.value[:processed],
                       failed: result.value[:failed]
                     )
          else
                     t("mcweb.admin.store.orders.bulk_processed", count: result.value[:processed])
          end
          redirect_to destination, notice: notice
        else
          redirect_to destination, alert: result.error || t("mcweb.flash.operation_failed")
        end
      end

      def export
        require_permission("store.orders.read")
        orders_scope = ::Commerce::Order.recent.includes(:user, :items)
        if params[:q].present?
          q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          orders_scope = orders_scope.where("order_number ILIKE ?", q)
        end
        if params[:status].present?
          orders_scope = orders_scope.where(status: params[:status])
        end
        orders = orders_scope.limit(5000)

        csv = ::CSV.generate(headers: true) do |rows|
          rows << [
            t("mcweb.admin.store.orders.export_headers.order_number"),
            t("mcweb.admin.store.orders.export_headers.customer"),
            t("mcweb.admin.store.orders.export_headers.status"),
            t("mcweb.admin.store.orders.export_headers.total"),
            t("mcweb.admin.store.orders.export_headers.created_at")
          ]
          orders.each do |order|
            rows << [
              order.order_number,
              order.user.username,
              order_status_label(order.status),
              order.total_cents / 100.0,
              order.created_at.iso8601
            ]
          end
        end

        send_data csv, filename: "orders-#{Time.current.strftime('%Y%m%d')}.csv", type: "text/csv"
      end

      def show
        fulfillments = @order.fulfillments.includes(:order_item)
        payment = @order.primary_succeeded_payment_record

        pending_refunds = @order.refunds.pending
        webhook_deliveries = Commerce::OrderWebhookDelivery.where(order_public_id: @order.public_id).order(created_at: :desc).limit(20)
        render inertia: "Admin/Generic/Show", props: {
          title: t("mcweb.admin.store.orders.show_title", number: @order.order_number),
          subtitle: order_status_label(@order.status),
          fields: order_detail_fields,
          sections: [
            {
              title: t("mcweb.admin.store.orders.section_items"),
              items: @order.items.map do |item|
                { label: item.product_name, value: "x#{item.quantity} #{format_money(item.total_cents, @order.currency)}" }
              end
            },
            {
              title: t("mcweb.admin.store.orders.section_fulfillments"),
              items: fulfillments.map do |fulfillment|
                { label: fulfillment.delivery_id, value: "#{fulfillment_status_label(fulfillment.status)} — #{fulfillment.order_item.product_name}" }
              end.presence || [ { label: t("mcweb.admin.store.orders.empty_fulfillments"), value: nil } ]
            },
            {
              title: t("mcweb.admin.store.orders.section_refunds"),
              items: @order.refunds.map do |refund|
                { label: l(refund.created_at, format: :short), value: "#{format_money(refund.amount_cents, @order.currency)} · #{refund_status_label(refund.status)}" }
              end.presence || [ { label: t("mcweb.admin.store.orders.empty_refunds"), value: nil } ]
            },
            {
              title: t("mcweb.admin.store.orders.section_restorations"),
              items: serialize_order_restorations(@order).map do |item|
                { label: item[:label], value: item[:amount_label] }
              end.presence || [ { label: t("mcweb.admin.store.orders.empty_restorations"), value: nil } ]
            },
            {
              title: t("mcweb.admin.store.orders.section_staff_notes"),
              items: @order.staff_notes.includes(:author).recent.limit(10).map do |note|
                { label: "#{note.author.username} · #{l(note.created_at, format: :short)}", value: note.body }
              end.presence || [ { label: t("mcweb.admin.store.orders.empty_staff_notes"), value: nil } ]
            },
            {
              title: t("mcweb.admin.store.orders.section_webhooks"),
              items: webhook_deliveries.map do |delivery|
                {
                  label: "#{delivery.event_type} · #{l(delivery.created_at, format: :short)}",
                  value: "#{webhook_delivery_status_label(delivery.status)} · HTTP #{delivery.response_code || t('mcweb.labels.not_available')} · #{delivery.url.truncate(60)}"
                }
              end.presence || [ { label: t("mcweb.admin.store.orders.empty_webhooks"), value: nil } ]
            }
          ],
          backUrl: admin_store_orders_path,
          actions: refund_actions(payment) + pending_refund_actions(pending_refunds) + shipping_actions,
          refundForm: refund_form_props(payment),
          shippingForm: shipping_form_props,
          staffNoteForm: { action_url: staff_note_admin_store_order_path(@order) }
        }
      end

      def staff_note
        result = Commerce::CreateOrderStaffNote.call(
          actor: current_user,
          order: @order,
          body: params[:body],
          visible_to_customer: params[:visible_to_customer]
        )

        if result.success?
          redirect_to admin_store_order_path(@order), notice: t("mcweb.flash.staff_note_added")
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def update_shipping
        if ActiveModel::Type::Boolean.new.cast(params[:mark_shipped]) && !current_user.permission?("store.orders.refund")
          return redirect_to admin_store_order_path(@order), alert: t("mcweb.flash.permission_denied")
        end

        result = Commerce::UpdateOrderShipping.call(
          order: @order,
          actor: current_user,
          tracking_number: params[:tracking_number],
          shipping_carrier: params[:shipping_carrier],
          mark_shipped: params[:mark_shipped]
        )

        if result.success?
          redirect_to admin_store_order_path(@order), notice: t("mcweb.flash.shipping_updated")
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def update
        if params[:reject_refund].present?
          return reject_refund
        end

        if params[:refund].present?
          return process_refund
        end

        if params[:shipping].present?
          return update_shipping
        end

        previous_status = @order.status
        if @order.update(order_params)
          if order_params[:status].present? && @order.status != previous_status
            if @order.status == "paid" && %w[pending awaiting_payment].include?(previous_status)
              Commerce::CompleteOrderPayment.call(order: @order, from_status: previous_status, staff_marked: true)
            else
              Commerce::NotifyOrderStatusChange.call(order: @order, from_status: previous_status)
            end
          end
          redirect_to admin_store_order_path(@order), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.order"))
        else
          redirect_to admin_store_order_path(@order), alert: @order.errors.full_messages.to_sentence
        end
      end

      private

      def set_order
        @order = ::Commerce::Order.find_by!(public_id: params[:id])
      end

      def order_params
        params.fetch(:order, {}).permit(:notes)
      end

      def refund_actions(payment)
        return [] unless payment && refundable_admin_status? && current_user.permission?("store.orders.refund")

        remaining = refund_remaining_cents(payment)
        return [] if remaining <= 0

        [ {
          label: t("mcweb.admin.store.orders.action_full_refund"),
          href: admin_store_order_path(@order),
          method: "patch",
          data: { refund: true, amount_cents: remaining }
        } ]
      end

      def refund_form_props(payment)
        return nil unless payment && refundable_admin_status? && current_user.permission?("store.orders.refund")

        remaining = refund_remaining_cents(payment)
        return nil if remaining <= 0

        {
          action_url: admin_store_order_path(@order),
          max_cents: remaining,
          max_label: format_money(remaining, @order.currency)
        }
      end

      def refund_remaining_cents(payment)
        reserved = @order.refunds.where(status: %w[pending completed]).sum(:amount_cents)
        [ payment.amount_cents - reserved, 0 ].max
      end

      def refund_amount_cents(payment)
        cents = params[:amount_cents].to_i
        if params[:refund_id].present?
          refund = @order.refunds.find_by(id: params[:refund_id])
          cents = refund.amount_cents if refund
          reserved = @order.refunds.where(status: %w[pending completed]).where.not(id: refund&.id).sum(:amount_cents)
        else
          reserved = @order.refunds.where(status: %w[pending completed]).sum(:amount_cents)
        end
        cents = refund_remaining_cents(payment) if cents <= 0
        remaining = payment.amount_cents - reserved
        [ cents, remaining ].min
      end

      def find_existing_refund
        return unless params[:refund_id].present?

        @order.refunds.find_by(id: params[:refund_id])
      end

      def pending_refund_actions(pending_refunds)
        return [] unless current_user.permission?("store.orders.refund")

        pending_refunds.flat_map do |refund|
          actions = [ {
            label: t("mcweb.admin.store.orders.action_approve_refund", amount: format_money(refund.amount_cents, @order.currency)),
            href: admin_store_order_path(@order),
            method: "patch",
            data: { refund: true, refund_id: refund.id, amount_cents: refund.amount_cents }
          } ]
          actions << {
            label: t("mcweb.admin.store.orders.action_reject_refund"),
            href: admin_store_order_path(@order),
            method: "patch",
            data: { reject_refund: true, refund_id: refund.id }
          }
          actions
        end
      end

      def reject_refund
        return redirect_to admin_store_order_path(@order), alert: t("mcweb.flash.permission_denied") unless current_user.permission?("store.orders.refund")

        refund = @order.refunds.pending.find(params[:refund_id])
        result = Commerce::RejectRefund.call(refund: refund, actor: current_user, reason: params[:reason])

        if result.success?
          redirect_to admin_store_order_path(@order), notice: t("mcweb.flash.refund_rejected")
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def process_refund
        return redirect_to admin_store_order_path(@order), alert: t("mcweb.flash.permission_denied") unless current_user.permission?("store.orders.refund")

        reject_superseded_pending_refunds! if params[:refund_id].blank?

        payment = @order.primary_succeeded_payment_record
        return redirect_to admin_store_order_path(@order), alert: t("mcweb.flash.no_refundable_payment") unless payment

        result = Commerce::ProcessRefund.call(
          order: @order,
          payment_record: payment,
          amount_cents: refund_amount_cents(payment),
          reason: params[:reason].presence || t("mcweb.admin.store.orders.admin_refund_reason"),
          approved_by: current_user,
          existing_refund: find_existing_refund
        )

        if result.success?
          redirect_to admin_store_order_path(@order), notice: t("mcweb.flash.refund_processed")
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def shipping_actions
        []
      end

      def shipping_form_props
        return nil unless Commerce::StoreFeatures.enabled?(:order_shipping_management)
        return nil unless current_user.permission?("store.orders.refund")

        {
          action_url: admin_store_order_path(@order),
          tracking_number: @order.tracking_number.to_s,
          shipping_carrier: @order.shipping_carrier.to_s,
          shipped: @order.shipped_at.present?
        }
      end

      def order_detail_fields
        fields = [
          { label: t("mcweb.admin.store.orders.field_customer"), value: @order.user.username },
          { label: t("mcweb.admin.store.orders.field_subtotal"), value: format_money(@order.subtotal_cents, @order.currency) }
        ]

        if Commerce::StoreFeatures.enabled?(:shipping)
          fields << {
            label: t("mcweb.admin.store.orders.field_shipping"),
            value: @order.shipping_cents.positive? ? format_money(@order.shipping_cents, @order.currency) : (@order.shipping_cents.zero? && @order.subtotal_cents.positive? ? t("mcweb.admin.store.orders.field_shipping_free") : t("mcweb.labels.not_available"))
          }
          fields << { label: t("mcweb.admin.store.orders.field_shipping_address"), value: format_shipping_address(@order.shipping_address).presence || t("mcweb.labels.not_available") }
          fields << { label: t("mcweb.admin.store.orders.field_shipping_method"), value: Commerce::ShippingMethods.label_for(@order.shipping_method).presence || t("mcweb.labels.not_available") }
        end

        if Commerce::StoreFeatures.enabled?(:order_shipping_management)
          fields << { label: t("mcweb.admin.store.orders.field_tracking_number"), value: @order.tracking_number.presence || t("mcweb.labels.not_available") }
          fields << { label: t("mcweb.admin.store.orders.field_carrier"), value: @order.shipping_carrier.presence || t("mcweb.labels.not_available") }
          fields << { label: t("mcweb.admin.store.orders.field_shipped_at"), value: @order.shipped_at ? l(@order.shipped_at, format: :long) : t("mcweb.labels.not_available") }
        end

        fields << { label: t("mcweb.admin.store.orders.field_discount"), value: @order.discount_cents.positive? ? "-#{format_money(@order.discount_cents, @order.currency)}#{@order.coupon ? " (#{@order.coupon.code})" : ""}" : t("mcweb.labels.not_available") }
        fields << { label: t("mcweb.admin.store.orders.field_gift_card"), value: @order.gift_card_amount_cents.positive? ? "-#{format_money(@order.gift_card_amount_cents, @order.currency)}#{@order.gift_card ? " (#{@order.gift_card.code})" : ""}" : t("mcweb.labels.not_available") }
        fields << { label: t("mcweb.admin.store.orders.field_store_credit"), value: @order.store_credit_amount_cents.positive? ? "-#{format_money(@order.store_credit_amount_cents, @order.currency)}" : t("mcweb.labels.not_available") }

        if Commerce::StoreFeatures.enabled?(:gift_wrap)
          fields << { label: t("mcweb.admin.store.orders.field_gift_wrap"), value: @order.gift_wrap_cents.positive? ? format_money(@order.gift_wrap_cents, @order.currency) : t("mcweb.labels.not_available") }
        end

        fields << { label: t("mcweb.admin.store.orders.field_buyer_notes"), value: @order.notes.presence || t("mcweb.labels.not_available") }
        fields << { label: t("mcweb.admin.store.orders.field_total"), value: format_money(@order.total_cents, @order.currency) }
        fields << { label: t("mcweb.admin.store.orders.field_created_at"), value: l(@order.created_at, format: :long) }
        fields
      end

      def refundable_admin_status?
        %w[paid fulfilled completed].include?(@order.status)
      end

      def bulk_order_actions
        actions = []
        if current_user.permission?("store.orders.refund")
          actions << { label: t("mcweb.admin.store.orders.bulk_cancel_pending"), action: "cancel_pending" }
          actions << { label: t("mcweb.admin.store.orders.bulk_mark_paid"), action: "mark_paid" }
          actions << { label: t("mcweb.admin.store.orders.bulk_mark_fulfilled"), action: "mark_fulfilled" }
        end
        actions
      end

      def require_bulk_update_permission!
        action = params[:action_type].to_s
        if %w[mark_paid mark_fulfilled cancel_pending].include?(action)
          require_permission("store.orders.refund")
        else
          require_permission("store.orders.read")
        end
      end

      def reject_superseded_pending_refunds!
        @order.refunds.pending.find_each do |refund|
          Commerce::RejectRefund.call(
            refund: refund,
            actor: current_user,
            reason: t("mcweb.admin.store.orders.superseded_refund_reason")
          )
        end
      end

      def order_status_tabs
        base_params = { q: params[:q].presence }.compact
        current = params[:status].to_s
        counts = order_counts_scope.group(:status).count
        total = counts.values.sum

        tabs = [ {
          label: t("mcweb.admin.store.orders.filter_all"),
          href: admin_store_orders_path(base_params),
          active: current.blank?,
          count: total
        } ]
        order_status_labels.each do |status, label|
          count = counts[status].to_i
          next if count.zero?

          tabs << {
            label: label,
            href: admin_store_orders_path(base_params.merge(status: status)),
            active: current == status,
            count: count
          }
        end
        tabs
      end

      def order_counts_scope
        scope = ::Commerce::Order.all
        if params[:q].present?
          q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          scope = scope.where("order_number ILIKE ?", q)
        end
        scope
      end

      def order_status_labels
        ::Commerce::Order::STATUSES.index_with { |status| order_status_label(status) }
      end
    end
  end
end
