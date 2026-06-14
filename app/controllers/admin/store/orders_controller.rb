# frozen_string_literal: true

module Admin
  module Store
    class OrdersController < BaseController
      before_action -> { require_permission("store.orders.read") }
      before_action :set_order, only: %i[show update]

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
          title: "订单",
          exportUrl: export_admin_store_orders_path(q: params[:q], status: params[:status]),
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
          end,
          pagination: pagy_props(@pagy)
        }
      end

      def export
        require_permission("store.orders.read")
        orders = ::Commerce::Order.recent.includes(:user, :items).limit(5000)

        csv = CSV.generate(headers: true) do |rows|
          rows << %w[订单号 客户 状态 金额 创建时间]
          orders.each do |order|
            rows << [
              order.order_number,
              order.user.username,
              order.status,
              order.total_cents / 100.0,
              order.created_at.iso8601
            ]
          end
        end

        send_data csv, filename: "orders-#{Time.current.strftime('%Y%m%d')}.csv", type: "text/csv"
      end

      def show
        fulfillments = @order.fulfillments.includes(:order_item)
        payment = @order.payment_records.where(status: "succeeded").order(created_at: :desc).first

        pending_refunds = @order.refunds.pending
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
            },
            {
              title: "退款记录",
              items: @order.refunds.map do |refund|
                { label: l(refund.created_at, format: :short), value: "#{format_money(refund.amount_cents, @order.currency)} · #{refund.status}" }
              end.presence || [{ label: "暂无退款", value: nil }]
            }
          ],
          backUrl: admin_store_orders_path,
          actions: refund_actions(payment) + pending_refund_actions(pending_refunds),
          refundForm: refund_form_props(payment)
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
          amount_cents: refund_amount_cents(payment),
          reason: params[:reason].presence || "Admin refund",
          approved_by: current_user,
          existing_refund: find_existing_refund
        )

        if result.success?
          redirect_to admin_store_order_path(@order), notice: "Refund processed."
        else
          redirect_to admin_store_order_path(@order), alert: service_error_message(result)
        end
      end

      def refund_actions(payment)
        return [] unless payment && %w[paid fulfilled].include?(@order.status) && current_user.permission?("store.orders.refund")

        [{
          label: "全额退款",
          href: admin_store_order_path(@order),
          method: "patch",
          data: { refund: true, amount_cents: payment.amount_cents }
        }]
      end

      def refund_form_props(payment)
        return nil unless payment && %w[paid fulfilled].include?(@order.status) && current_user.permission?("store.orders.refund")

        refunded_cents = @order.refunds.where(status: %w[pending completed]).sum(:amount_cents)
        remaining = [ payment.amount_cents - refunded_cents, 0 ].max
        return nil if remaining <= 0

        {
          action_url: admin_store_order_path(@order),
          max_cents: remaining,
          max_label: format_money(remaining, @order.currency)
        }
      end

      def refund_amount_cents(payment)
        cents = params[:amount_cents].to_i
        if params[:refund_id].present?
          refund = @order.refunds.find_by(id: params[:refund_id])
          cents = refund.amount_cents if refund
        end
        cents = payment.amount_cents if cents <= 0
        refunded = @order.refunds.where(status: %w[pending completed]).where.not(id: params[:refund_id]).sum(:amount_cents)
        remaining = payment.amount_cents - refunded
        [ cents, remaining ].min
      end

      def find_existing_refund
        return @order.refunds.find_by(id: params[:refund_id]) if params[:refund_id].present?

        @order.refunds.pending.order(created_at: :asc).first
      end

      def pending_refund_actions(pending_refunds)
        pending_refunds.map do |refund|
          {
            label: "批准退款申请 #{format_money(refund.amount_cents, @order.currency)}",
            href: admin_store_order_path(@order),
            method: "patch",
            data: { refund: true, refund_id: refund.id, amount_cents: refund.amount_cents }
          }
        end
      end
    end
  end
end
