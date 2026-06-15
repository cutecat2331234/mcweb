# frozen_string_literal: true

module Admin
  module Forum
    class WebhookDeliveriesController < BaseController
      before_action -> { require_permission("system.settings.manage") }

      def index
        scope = Community::SavedSearchWebhookDelivery.includes(saved_search: :user).recent
        if params[:status].present?
          scope = scope.where(status: params[:status])
        end
        @pagy, deliveries = pagy(scope, limit: 50)

        render inertia: "Admin/Generic/Index", props: {
          title: "保存搜索 Webhook 投递",
          columns: [
            admin_column(:search, "搜索"),
            admin_column(:user, "用户"),
            admin_column(:status, "状态"),
            admin_column(:code, "响应码"),
            admin_column(:created_at, "时间")
          ],
          rows: deliveries.map do |delivery|
            admin_row(
              search: delivery.saved_search&.name,
              user: delivery.saved_search&.user&.username,
              status: delivery.status,
              code: delivery.response_code&.to_s || "—",
              created_at: l(delivery.created_at, format: :short)
            )
          end,
          pagination: pagy_props(@pagy)
        }
      end
    end
  end
end
