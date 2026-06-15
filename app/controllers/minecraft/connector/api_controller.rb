# frozen_string_literal: true

module Minecraft
  module Connector
    class ApiController < ActionController::API
      include ServiceResponder

      before_action :set_server
      before_action :authenticate_connector!

      def heartbeat
        @server.heartbeat!
        render json: { status: "ok", server_id: @server.public_id }
      end

      def tasks
        result = Minecraft::TaskDispatcher.call(server: @server, action: :claim)

        if result.success?
          render json: { tasks: result.value[:tasks].map { |task| serialize_task(task) } }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def complete
        result = Minecraft::TaskDispatcher.call(
          server: @server,
          task_id: params[:id],
          result: task_result_params,
          action: :complete
        )

        if result.success?
          render json: { task: serialize_task(result.value[:task]) }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      private

      def set_server
        @server = Minecraft::Server.find_by!(public_id: params[:server_id])
      end

      def authenticate_connector!
        auth_result = Minecraft::ConnectorAuthenticator.call(
          server: @server,
          payload: signed_payload,
          signature: request.headers["X-Connector-Signature"].to_s,
          timestamp: request.headers["X-Connector-Timestamp"]
        )

        return if auth_result.success?

        render json: { error: service_error_message(auth_result) }, status: :unauthorized
        nil
      end

      def signed_payload
        request.raw_post.presence || request.request_parameters.to_json
      end

      def task_result_params
        params.fetch(:result, {}).permit(:success, :status, :message, :error, :output, :detail, data: {}).to_h
      end

      def serialize_task(task)
        {
          id: task.id,
          task_type: task.task_type,
          payload: task.payload,
          status: task.status,
          delivery_id: task.delivery_id
        }
      end
    end
  end
end
