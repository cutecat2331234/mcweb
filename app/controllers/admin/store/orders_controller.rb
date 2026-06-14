# frozen_string_literal: true

module Admin
  module Store
    class OrdersController < BaseController
      before_action -> { require_permission("store.orders.read") }
      before_action :set_order, only: %i[show update]

      def index
        orders = ::Commerce::Order.recent.limit(50)

        render inertia: "Admin/Generic/Index", props: {
          title: "订单",
          columns: [
            admin_column(:order_number, "订单号", link: true),
            admin_column(:customer, "客户"),
            admin_column(:status, "状态"),
            admin_column(:total, "金额")
          ],
          rows: orders.map do |order|
            admin_row(
              order_number: order.order_number,
              customer: order.user.username,
              status: order.status,
              total: format_money(order.total_cents, order.currency),
              url: admin_store_order_path(order)
            )
          end
        }
      end

      def show
        fulfillments = @order.fulfillments.includes(:order_item)
        payment = @order.payment_records.where(status: "succeeded").order(created_at: :desc).first

        render inertia: "Admin/Generic/Show", props: {
          title: "订单 #{@order.order_number}",
          subtitle: @order.status,
          fields: [
            { label: "客户", value: @order.user.username },
            { label: "总额", value: format_money(@order.total_cents, @order.currency) },
            { label: "创建时间", value: l(@order.created_at, format: :long) }
          ],
          sections: [
            {
              title: "商品",
              items: @order.items.map do |item|
                { label: item.product_name, value: "x#{item.quantity} #{format_money(item.total_cents, @order.currency)}" }
              end
            },
            {
              title: "发货",
              items: fulfillments.map do |fulfillment|
                { label: fulfillment.delivery_id, value: "#{fulfillment.status} — #{fulfillment.order_item.product_name}" }
              end.presence || [{ label: "暂无发货记录", value: nil }]
            }
          ],
          backUrl: admin_store_orders_path,
          actions: refund_actions(payment)
        }
      end

      def update
        if params[:refund].present?
          return process_refund
        end

        if @order.update(order_params)
          redirect_to admin_store_order_path(@order), notice: "Order updated."
        else
          redirect_to admin_store_order_path(@order), alert: @order.errors.full_messages.to_sentence
        end
      end

      private

      def set_order
        @order = ::Commerce::Order.find_by!(public_id: params[:id])
      end

      def order_params
        params.fetch(:order, {}).permit(:status, :notes)
      end

      def process_refund
        return redirect_to admin_store_order_path(@order), alert: "Not authorized." unless current_user.permission?("store.orders.refund")

        payment = @order.payment_records.where(status: "succeeded").order(created_at: :desc).first
        return redirect_to admin_store_order_path(@order), alert: "No refundable payment." unless payment

        result = Commerce::ProcessRefund.call(
          order: @order,
          payment_record: payment,
          amount_cents: payment.amount_cents,
          reason: "Admin refund",
          approved_by: current_user
        )

        if result.success?
          redirect_to admin_store_order_path(@order), notice: "Refund processed."
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def refund_actions(payment)
        return [] unless payment && @order.status == "paid" && current_user.permission?("store.orders.refund")

        [{
          label: "全额退款",
          href: admin_store_order_path(@order),
          method: "patch",
          data: { refund: true }
        }]
      end
    end
  end
end
