# frozen_string_literal: true



module Admin
  module Store
    class FulfillmentsController < BaseController
      before_action -> { require_permission("minecraft.fulfillments.retry") }

      before_action :set_fulfillment, only: %i[show update]



      def index
        fulfillments = ::Commerce::Fulfillment.order(created_at: :desc).limit(50)



        render inertia: "Admin/Generic/Index", props: {

          title: t("mcweb.admin.store.fulfillments.title"),

          columns: [

            admin_column(:delivery_id, t("mcweb.admin.store.fulfillments.col_delivery_id"), link: true),

            admin_column(:status, t("mcweb.admin.store.fulfillments.col_status")),

            admin_column(:order, t("mcweb.admin.store.fulfillments.col_order")),

            admin_column(:product, t("mcweb.admin.store.fulfillments.col_product"))

          ],

          rows: fulfillments.map do |fulfillment|
            admin_row(

              delivery_id: fulfillment.delivery_id,

              status: fulfillment_status_label(fulfillment.status),

              order: fulfillment.order.order_number,

              product: fulfillment.order_item.product_name,

              url: admin_store_fulfillment_path(fulfillment)

            )
          end

        }
      end



      def show
        server = resolve_fulfillment_server(@fulfillment)
        render inertia: "Admin/Store/Fulfillments/Show", props: {

          fulfillment: {

            id: @fulfillment.id,

            delivery_id: @fulfillment.delivery_id,

            status: fulfillment_status_label(@fulfillment.status),

            order_number: @fulfillment.order.order_number,

            product_name: @fulfillment.order_item.product_name,

            attempts_count: @fulfillment.attempts_count,

            last_error: @fulfillment.last_error,

            target_server: server&.name,

            target_server_process_state: server&.process_state,

            target_server_url: server ? admin_minecraft_server_path(server) : nil

          }

        }
      end



      def update
        if retry_fulfillment?

          result = Commerce::RetryFulfillment.call(fulfillment: @fulfillment)

          if result.failure?

            redirect_to admin_store_fulfillment_path(@fulfillment), alert: service_error_message(result)

          else

            redirect_to admin_store_fulfillment_path(@fulfillment), notice: t("mcweb.flash.fulfillment_requeued")

          end

        elsif @fulfillment.update(fulfillment_params)

          redirect_to admin_store_fulfillment_path(@fulfillment), notice: t("mcweb.flash.fulfillment_updated")

        else

          redirect_to admin_store_fulfillment_path(@fulfillment), alert: @fulfillment.errors.full_messages.to_sentence

        end
      end



      private



      def set_fulfillment
        @fulfillment = ::Commerce::Fulfillment.find(params[:id])
      end



      def fulfillment_params
        params.expect(fulfillment: [ :last_error ])[:fulfillment]
      end



      def retry_fulfillment?
        params[:retry] == "1"
      end

      def resolve_fulfillment_server(fulfillment)
        snapshot = fulfillment.order_item.fulfillment_snapshot || {}
        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        server_public_id = config["server_id"] || config[:server_id] || config["minecraft_server_id"] || config[:minecraft_server_id]
        return nil if server_public_id.blank?

        Minecraft::Server.find_by(public_id: server_public_id.to_s)
      end
    end
  end
end
