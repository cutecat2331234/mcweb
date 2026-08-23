# frozen_string_literal: true

module Minecraft
  module Nodes
    class ApiController < ActionController::API
      include ServiceResponder
      include InertiaApplicationBoundary

      before_action :set_node
      before_action :authenticate_node!

      def heartbeat
        result = Minecraft::RecordNodeHeartbeat.call(node: @node, payload: node_payload)
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def tasks
        result = Minecraft::NodeTaskDispatcher.call(node: @node, action: :claim)

        if result.success?
          render json: { tasks: result.value[:tasks].map { |task| serialize_task(task) } }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def complete
        result = Minecraft::NodeTaskDispatcher.call(
          node: @node,
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

      def next_operation
        result = Minecraft::NodeOperationDispatcher.call(node: @node, action: :claim)

        if result.success?
          render json: { batch: serialize_operation_batch(result.value[:batch]) }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def renew_operation_lease
        result = Minecraft::NodeOperationDispatcher.call(
          node: @node,
          batch_id: params[:id],
          envelope: node_payload,
          action: :lease
        )

        if result.success?
          render json: {
            acknowledged: result.value[:acknowledged],
            lease_expires_at: result.value[:batch]&.lease_expires_at&.iso8601
          }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def complete_operation
        result = Minecraft::NodeOperationDispatcher.call(
          node: @node,
          batch_id: params[:id],
          envelope: node_payload,
          action: :complete
        )

        if result.success?
          render json: {
            acknowledgement_id: result.value[:acknowledgement_id],
            acknowledged: result.value[:acknowledged],
            status: result.value[:batch].status
          }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def acknowledge_operation
        result = Minecraft::NodeOperationDispatcher.call(
          node: @node,
          batch_id: params[:id],
          envelope: node_payload,
          action: :acknowledge
        )

        if result.success?
          render json: {
            acknowledged: result.value[:acknowledged],
            status: result.value[:batch].status
          }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def report
        server = Minecraft::Server.find_by!(public_id: params[:server_id])
        result = Minecraft::SyncInstanceReport.call(node: @node, server: server, payload: node_payload)

        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
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

      def node_payload
        @node_payload ||= begin
          body = request.request_parameters
          body = JSON.parse(request.raw_post) if body.blank? && request.raw_post.present?
          body.deep_stringify_keys
        end
      end

      def signed_payload
        return request.raw_post if request.raw_post.present?
        return "" if request.get? || request.head?

        request.request_parameters.to_json
      end

      def task_result_params
        result = params.fetch(:result, {})
        return {} unless result.respond_to?(:to_unsafe_h)

        result.to_unsafe_h.stringify_keys
      end

      def serialize_task(task)
        {
          # IDs cross a Go JSON boundary, so serialize them as strings instead of
          # IEEE-754 numbers that cannot represent every Rails bigint exactly.
          id: task.id.to_s,
          task_type: task.task_type,
          payload: task.payload,
          status: task.status,
          delivery_id: task.delivery_id,
          server_id: task.server&.public_id
        }
      end

      def serialize_operation_batch(batch)
        return if batch.nil?

        {
          protocol_version: batch.payload.fetch("protocol_version", 2),
          id: batch.public_id,
          operation_id: batch.operation.public_id,
          delivery_id: batch.delivery_id,
          operation_type: batch.operation.operation_type,
          payload_digest: batch.payload_digest,
          shared_payload: batch.payload.fetch("shared_payload", {}),
          targets: batch.payload.fetch("targets", [])
        }
      end
    end
  end
end
