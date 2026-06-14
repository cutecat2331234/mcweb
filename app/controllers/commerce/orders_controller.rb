# frozen_string_literal: true

module Commerce
  class OrdersController < ApplicationController
    before_action :require_login
    before_action :set_order, only: %i[show cancel refund receipt receipt_pdf reorder refresh_download]

    def index
      orders_scope = Commerce::Order.where(user: current_user).includes(:items).recent
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        orders_scope = orders_scope.where("order_number ILIKE ?", q)
      end
      if params[:status].present?
        orders_scope = orders_scope.where(status: params[:status])
      end

      @pagy, orders = pagy(orders_scope, limit: 20)

      render inertia: "Commerce/Orders/Index", props: {
        orders: orders.map { |order| serialize_order_list_item(order) },
        pagination: pagy_props(@pagy),
        query: params[:q].to_s,
        status: params[:status].to_s,
        statusOptions: Commerce::Order::STATUSES.map { |s| { value: s, label: order_status_label(s) } }
      }
    end

    def show
      render inertia: "Commerce/Orders/Show", props: {
        order: serialize_order_detail(@order)
      }
    end

    def cancel
      result = Commerce::CancelOrder.call(order: @order, actor: current_user)

      if result.success?
        redirect_to store_order_path(@order), notice: "订单已取消。"
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def refund
      result = Commerce::RequestRefund.call(
        order: @order,
        user: current_user,
        reason: params[:reason]
      )

      if result.success?
        redirect_to store_order_path(@order), notice: "退款申请已提交，请等待审核。"
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def receipt
      unless %w[paid processing fulfilling fulfilled completed refunded].include?(@order.status)
        return redirect_to store_order_path(@order), alert: "该订单暂无收据。"
      end

      render "commerce/orders/receipt", layout: false
    end

    def receipt_pdf
      unless %w[paid processing fulfilling fulfilled completed refunded].include?(@order.status)
        return redirect_to store_order_path(@order), alert: "该订单暂无收据。"
      end

      result = Commerce::GenerateOrderReceiptPdf.call(order: @order)
      if result.success?
        send_data result.value,
                  filename: "receipt-#{@order.order_number}.pdf",
                  type: "application/pdf",
                  disposition: "attachment"
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def reorder
      result = Commerce::ReorderFromOrder.call(user: current_user, order: @order)

      if result.success?
        notice = "已将 #{result.value[:added]} 件商品加入购物车。"
        notice += " 跳过：#{result.value[:skipped].join('、')}" if result.value[:skipped].any?
        redirect_to store_cart_path, notice: notice
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def refresh_download
      order_item = @order.items.find_by(id: params[:order_item_id])
      return redirect_to store_order_path(@order), alert: "商品不存在。" unless order_item

      result = Commerce::GenerateDownloadToken.call(order_item: order_item, user: current_user)
      if result.success?
        redirect_to store_download_path(result.value[:token])
      else
        redirect_to store_order_path(@order), alert: service_error_message(result)
      end
    end

    def new
      cart = Commerce::Cart.find_by(user: current_user)
      redirect_to store_cart_path, alert: "Your cart is empty." if cart.nil? || cart.empty?
    end

    def create
      cart = Commerce::Cart.find_by(user: current_user)
      return redirect_to store_cart_path, alert: "Your cart is empty." if cart.nil? || cart.empty?

      result = Commerce::CreateOrder.call(
        cart: cart,
        user: current_user,
        notes: order_params[:notes]
      )

      if result.success?
        redirect_to store_order_path(result.value), notice: "Order created."
      else
        redirect_to new_store_order_path, alert: service_error_message(result)
      end
    end

    private

    def set_order
      @order = Commerce::Order.where(user: current_user)
                              .includes(:items, :fulfillments, :refunds, :events, items: { product: :forum_topic })
                              .find_by!(public_id: params[:id])
    end

    def order_params
      params.fetch(:order, {}).permit(:notes)
    end
  end
end
