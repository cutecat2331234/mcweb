# frozen_string_literal: true

module Admin
  module Store
    class FulfillmentsController < BaseController
      before_action -> { require_permission("admin.store.fulfill") }
      before_action :set_fulfillment, only: %i[show update]

      def index
        @fulfillments = ::Commerce::Fulfillment.order(created_at: :desc).limit(50)
      end

      def show
      end

      def update
        result = Commerce::CreateFulfillment.call(order_item: @fulfillment.order_item) if retry_fulfillment?

        if result&.failure?
          redirect_to admin_store_fulfillment_path(@fulfillment), alert: service_error_message(result)
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
