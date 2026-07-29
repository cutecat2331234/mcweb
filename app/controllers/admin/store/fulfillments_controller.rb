# frozen_string_literal: true

module Admin
  module Store
    class FulfillmentsController < BaseController
      before_action -> { require_permission("store.fulfillments.read") }
      before_action :set_fulfillment, only: %i[show authorize_action execute_action]

      def index
        scope = ::Commerce::Fulfillment.includes(:order, :order_item).order(created_at: :desc)
        scope = scope.where(status: params[:status]) if ::Commerce::Fulfillment.statuses.key?(params[:status])
        @pagy, fulfillments = pagy(:offset, scope, limit: 50)

        render inertia: "Admin/Store/Fulfillments/Index", props: {
          summary: fulfillment_summary,
          filters: {
            status: params[:status].presence
          },
          status_options: fulfillment_status_options,
          rows: fulfillments.map { |fulfillment| serialize_fulfillment_row(fulfillment) },
          pagination: pagy_props(@pagy)
        }
      end

      def show
        server = resolve_fulfillment_server(@fulfillment)
        render inertia: "Admin/Store/Fulfillments/Show", props: {
          fulfillment: serialize_fulfillment(@fulfillment, server),
          attempts: @fulfillment.attempts.includes(:actor).recent.limit(100).map do |attempt|
            serialize_attempt(attempt)
          end,
          permissions: {
            retry: current_user.permission?("store.fulfillments.retry"),
            cancel: current_user.permission?("store.fulfillments.cancel")
          },
          paths: {
            index: admin_store_fulfillments_path,
            authorize: authorize_action_admin_store_fulfillment_path(@fulfillment),
            execute: execute_action_admin_store_fulfillment_path(@fulfillment)
          }
        }
      end

      def authorize_action
        result = manual_action(authorize_only: true).call
        return render_action_error(result) if result.failure?

        value = result.value
        response.set_header("Cache-Control", "private, no-store")
        render json: {
          authorization_token: value[:authorization_token],
          confirmation: value[:confirmation],
          request_id: value[:request_id],
          expires_in: value[:expires_in],
          preview_items: fulfillment_preview_items(value[:preview])
        }
      end

      def execute_action
        result = manual_action.call
        return render_action_error(result) if result.failure?

        response.set_header("Cache-Control", "private, no-store")
        render json: {
          request_id: action_params[:request_id],
          idempotent: result.value[:idempotent],
          status: result.value[:fulfillment].status,
          message: t("mcweb.admin.store.fulfillments.actions.#{action_params[:action]}.completed")
        }
      end

      private

      def set_fulfillment
        @fulfillment = ::Commerce::Fulfillment.find(params[:id])
      end

      def action_params
        nested = params.fetch(:fulfillment_action, {}).permit(:action)
        nested.merge(
          params.permit(:request_id, :reason, :authorization_token, :confirmation)
        )
      end

      def manual_action(authorize_only: false)
        ::Commerce::ManualFulfillmentAction.new(
          actor: current_user,
          fulfillment: @fulfillment,
          action: action_params[:action],
          request_id: action_params[:request_id],
          reason: action_params[:reason],
          authorization_token: action_params[:authorization_token],
          confirmation: action_params[:confirmation],
          authorize_only: authorize_only,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def render_action_error(result)
        response.set_header("Cache-Control", "private, no-store")
        render json: { error: service_error_message(result) }, status: service_error_status(result)
      end

      def fulfillment_summary
        {
          total: ::Commerce::Fulfillment.count,
          pending: ::Commerce::Fulfillment.where(status: %w[pending processing]).count,
          failed: ::Commerce::Fulfillment.failed.count,
          exhausted: ::Commerce::Fulfillment.failed.where("attempts_count >= max_attempts").count
        }
      end

      def fulfillment_status_options
        ::Commerce::Fulfillment.statuses.keys.map do |status|
          { value: status, label: fulfillment_status_label(status) }
        end
      end

      def serialize_fulfillment_row(fulfillment)
        {
          id: fulfillment.id,
          delivery_id: fulfillment.delivery_id,
          status: fulfillment.status,
          status_label: fulfillment_status_label(fulfillment.status),
          order_number: fulfillment.order.order_number,
          product_name: fulfillment.order_item.product_name,
          attempts_count: fulfillment.attempts_count,
          max_attempts: fulfillment.max_attempts,
          next_attempt_at: fulfillment.next_attempt_at&.iso8601,
          error_label: fulfillment_error_label(fulfillment.last_error),
          url: admin_store_fulfillment_path(fulfillment)
        }
      end

      def serialize_fulfillment(fulfillment, server)
        serialize_fulfillment_row(fulfillment).merge(
          fulfilled_at: fulfillment.fulfilled_at&.iso8601,
          cancelled_at: fulfillment.cancelled_at&.iso8601,
          cancel_reason: fulfillment.cancel_reason,
          retryable: fulfillment.retryable?,
          cancellable: fulfillment.pending? || fulfillment.processing? || fulfillment.failed?,
          exhausted: fulfillment.exhausted?,
          target_server: server&.name,
          target_server_process_state: server&.process_state,
          target_server_url: server ? admin_minecraft_server_path(server) : nil
        )
      end

      def serialize_attempt(attempt)
        {
          id: attempt.id,
          number: attempt.attempt_number,
          action: attempt.action,
          action_label: t(
            "mcweb.admin.store.fulfillments.attempt_actions.#{attempt.action}",
            default: t("mcweb.labels.not_available")
          ),
          trigger: attempt.trigger,
          trigger_label: t(
            "mcweb.admin.store.fulfillments.attempt_triggers.#{attempt.trigger}",
            default: t("mcweb.labels.not_available")
          ),
          status: attempt.status,
          status_label: t(
            "mcweb.admin.store.fulfillments.attempt_statuses.#{attempt.status}",
            default: t("mcweb.labels.not_available")
          ),
          error_label: fulfillment_error_label(attempt.error_code),
          reason: attempt.reason,
          actor: attempt.actor&.username,
          started_at: attempt.started_at&.iso8601 || attempt.created_at.iso8601,
          completed_at: attempt.completed_at&.iso8601,
          next_retry_at: attempt.next_retry_at&.iso8601
        }
      end

      def fulfillment_preview_items(preview)
        [
          [ "delivery_id", preview[:delivery_id] ],
          [ "order", preview[:order_number] ],
          [ "product", preview[:product_name] ],
          [ "current_status", fulfillment_status_label(preview[:current_status]) ],
          [ "next_status", fulfillment_status_label(preview[:next_status]) ],
          [ "attempts", "#{preview[:attempts_count]} / #{preview[:max_attempts]}" ],
          [
            "inventory",
            t(
              "mcweb.admin.store.fulfillments.inventory_statuses.#{preview[:inventory_status]}",
              default: t("mcweb.labels.not_available")
            )
          ],
          [
            "entitlement",
            preview[:active_entitlement] ? t("mcweb.labels.enabled") : t("mcweb.labels.disabled")
          ],
          [ "active_tasks", preview[:active_connector_tasks] ]
        ].map do |key, value|
          {
            label: t("mcweb.admin.store.fulfillments.preview.#{key}"),
            value: value.to_s
          }
        end
      end

      def fulfillment_error_label(code)
        return nil if code.blank?

        t(
          "mcweb.admin.store.fulfillments.error_codes.#{::Commerce::Fulfillment.normalize_error_code(code)}",
          default: t("mcweb.admin.store.fulfillments.error_codes.fulfillment_failed")
        )
      end

      def resolve_fulfillment_server(fulfillment)
        snapshot = fulfillment.order_item.fulfillment_snapshot || {}
        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        server_public_id =
          config["server_id"] || config[:server_id] ||
          config["minecraft_server_id"] || config[:minecraft_server_id]
        return nil if server_public_id.blank?

        Minecraft::Server.find_by(public_id: server_public_id.to_s)
      end
    end
  end
end
