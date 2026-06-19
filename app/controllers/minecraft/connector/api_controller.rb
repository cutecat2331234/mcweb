# frozen_string_literal: true

module Minecraft
  module Connector
    class ApiController < ActionController::API
      include ServiceResponder

      before_action :set_server
      before_action :authenticate_connector!

      def heartbeat
        result = Minecraft::RecordHeartbeat.call(server: @server, payload: connector_payload)
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def link_codes
        result = Minecraft::GenerateLinkCode.call(
          server: @server,
          minecraft_uuid: connector_payload.fetch("uuid"),
          minecraft_username: connector_payload.fetch("username"),
          identity_type: connector_payload.fetch("platform", "java")
        )

        if result.success?
          player_ref = Minecraft::PlayerRef.resolve(
            uuid: connector_payload.fetch("uuid"),
            platform: connector_payload.fetch("platform", "java"),
            username: connector_payload.fetch("username")
          )
          render json: {
            code: result.value[:code],
            expires_at: result.value[:link_code].expires_at.iso8601,
            player_id: player_ref.public_id,
            link_url: "#{request.base_url}/app/minecraft/link"
          }
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def presence
        result = Minecraft::SyncPresence.call(server: @server, payload: connector_payload)
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def profile_fields
        result = Minecraft::SyncProfileFields.call(payload: connector_payload)
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def permission_groups
        result = Minecraft::SyncPermissionGroups.call(payload: connector_payload)
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def server_stats
        result = Minecraft::RecordHeartbeat.call(server: @server, payload: connector_payload)
        if result.success?
          render json: result.value.merge(stats: true)
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
      end

      def fetch_config
        result = Minecraft::FetchConnectorConfig.call(server: @server)
        render json: result.value
      end

      def whois
        result = Minecraft::LookupPlayer.call(
          uuid: connector_payload["uuid"],
          username: connector_payload["username"],
          platform: connector_payload.fetch("platform", "java")
        )
        render json: result.value
      end

      def events
        payload = connector_payload.fetch("payload", {}).deep_stringify_keys
        %w[uuid username platform player_id server_id].each do |key|
          payload[key] = connector_payload[key] if connector_payload[key].present?
        end

        result = Minecraft::Integration::ActionRunner.call(
          event_key: connector_payload.fetch("event"),
          event_id: connector_payload.fetch("event_id", SecureRandom.uuid),
          payload: payload
        )
        if result.success?
          render json: result.value
        else
          render json: { error: service_error_message(result) }, status: :unprocessable_entity
        end
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
        false
      end

      def connector_payload
        @connector_payload ||= begin
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
