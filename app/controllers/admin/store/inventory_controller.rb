# frozen_string_literal: true

module Admin
  module Store
    class InventoryController < BaseController
      before_action -> { require_permission("store.inventory.read") }, only: :index
      before_action -> { require_permission("store.inventory.adjust") }, only: %i[authorize_adjustment adjust]
      before_action :set_target, only: %i[authorize_adjustment adjust]

      def index
        result = ::Commerce::InventoryHealth.call
        render inertia: "Admin/Store/Inventory/Index", props: result.value.merge(
          permissions: {
            adjust: current_user.permission?("store.inventory.adjust"),
            recover: current_user.permission?("store.inventory.recover")
          },
          paths: {
            authorize: admin_store_inventory_authorize_adjustment_path,
            adjust: admin_store_inventory_adjust_path
          }
        )
      end

      def authorize_adjustment
        result = ::Commerce::InventoryAdjustment.call(
          actor: current_user,
          target: @target,
          delta: adjustment_params[:delta],
          request_id: adjustment_params[:request_id],
          reason: adjustment_params[:reason],
          authorize_only: true
        )
        render_service_result(result)
      end

      def adjust
        result = ::Commerce::InventoryAdjustment.call(
          actor: current_user,
          target: @target,
          delta: adjustment_params[:delta],
          request_id: adjustment_params[:request_id],
          reason: adjustment_params[:reason],
          authorization_token: adjustment_params[:authorization_token],
          confirmation: adjustment_params[:confirmation],
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        render_service_result(result)
      end

      private

      def set_target
        @target = case adjustment_params[:target_type]
                  when "product"
                    ::Commerce::Product.find_by!(public_id: adjustment_params[:target_id])
                  when "variant"
                    ::Commerce::ProductVariant.find(adjustment_params[:target_id])
                  else
                    raise ActiveRecord::RecordNotFound
                  end
      end

      def adjustment_params
        params.expect(adjustment: %i[
          target_type target_id delta request_id reason authorization_token confirmation
        ])
      end

      def render_service_result(result)
        response.set_header("Cache-Control", "private, no-store")
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: service_error_status(result)
        end
      end
    end
  end
end
