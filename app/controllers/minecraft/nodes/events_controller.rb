# frozen_string_literal: true

module Minecraft
  module Nodes
    class EventsController < ActionController::API
      include ActionController::Live
      include ServiceResponder

      before_action :set_node
      before_action :authenticate_node!

      def show
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["Connection"] = "keep-alive"
        response.headers["X-Accel-Buffering"] = "no"

        since = parse_since_param
        deadline = Time.current + 55.seconds

        while Time.current < deadline
          @node.reload
          if @node.tasks_wake_at.present? && @node.tasks_wake_at > since
            response.stream.write("event: tasks_available\ndata: {\"wake_at\":\"#{@node.tasks_wake_at.iso8601}\"}\n\n")
            break
          end
          sleep 0.25
        end
      ensure
        response.stream.close
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

        Time.zone.parse(params[:since].to_s)
      rescue ArgumentError
        1.hour.ago
      end
    end
  end
end
