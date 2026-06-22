# frozen_string_literal: true

module Minecraft
  module Nodes
    class EventsController < ActionController::API
      include ServiceResponder

      before_action :set_node
      before_action :authenticate_node!

      def show
        since = parse_since_param
        @node.reload

        if @node.tasks_wake_at.present? && @node.tasks_wake_at > since
          render json: {
            event: "tasks_available",
            wake_at: @node.tasks_wake_at.iso8601(3)
          }
        else
          head :no_content
        end
      end

      private

      def set_node
        @node = Minecraft::Node.find_by!(public_id: params[:node_id])
      end

      def authenticate_node!
        auth_result = Minecraft::NodeAuthenticator.call(
          node: @node,
          payload: signed_payload,
          signature: request.headers["X-Node-Signature"].to_s,
          timestamp: request.headers["X-Node-Timestamp"]
        )

        return if auth_result.success?

        render json: { error: service_error_message(auth_result) }, status: :unauthorized
        false
      end

      def signed_payload
        return request.raw_post if request.raw_post.present?
        return "" if request.get? || request.head?

        request.request_parameters.to_json
      end

      def parse_since_param
        return 1.hour.ago if params[:since].blank?

        parsed = Time.zone.parse(params[:since].to_s)
        parsed.presence || 1.hour.ago
      rescue ArgumentError
        1.hour.ago
      end
    end
  end
end
