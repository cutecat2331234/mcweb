# frozen_string_literal: true

module Admin
  module Store
    class FulfillmentsController < BaseController
      before_action -> { require_permission("minecraft.fulfillments.retry") }
      before_action :set_fulfillment, only: %i[show update]

      def index
        fulfillments = ::Commerce::Fulfillment.order(created_at: :desc).limit(50)

        render inertia: "Admin/Generic/Index", props: {
          title: "发货记录",
          columns: [
            admin_column(:delivery_id, "Delivery ID", link: true),
            admin_column(:status, "状态"),
            admin_column(:order, "订单"),
            admin_column(:product, "商品")
          ],
          rows: fulfillments.map do |fulfillment|
            admin_row(
              delivery_id: fulfillment.delivery_id,
              status: fulfillment.status,
              order: fulfillment.order.order_number,
              product: fulfillment.order_item.product_name,
              url: admin_store_fulfillment_path(fulfillment)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Store/Fulfillments/Show", props: {
          fulfillment: {
            id: @fulfillment.id,
            delivery_id: @fulfillment.delivery_id,
            status: @fulfillment.status,
            order_number: @fulfillment.order.order_number,
            product_name: @fulfillment.order_item.product_name,
            attempts_count: @fulfillment.attempts_count,
            last_error: @fulfillment.last_error
          }
        }
      end

      def update
        if retry_fulfillment?
          result = Commerce::RetryFulfillment.call(fulfillment: @fulfillment)
          if result.failure?
            redirect_to admin_store_fulfillment_path(@fulfillment), alert: service_error_message(result)
          else
            redirect_to admin_store_fulfillment_path(@fulfillment), notice: "已重新排队发货。"
          end
        elsif @fulfillment.update(fulfillment_params)
          redirect_to admin_store_fulfillment_path(@fulfillment), notice: "Fulfillment updated."
        else
          redirect_to admin_store_fulfillment_path(@fulfillment), alert: @fulfillment.errors.full_messages.to_sentence
        end
      end

      private

      def set_fulfillment
        @fulfillment = ::Commerce::Fulfillment.find(params[:id])
      end

      def fulfillment_params
        params.expect(fulfillment: %i[status last_error])[:fulfillment]
      end

      def retry_fulfillment?
        params[:retry] == "1"
      end
    end
  end
end
