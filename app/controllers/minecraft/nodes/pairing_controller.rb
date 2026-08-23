# frozen_string_literal: true

module Minecraft
  module Nodes
    class PairingController < ActionController::API
      include InertiaApplicationBoundary

      def create
        rate_result = Administration::RateLimiter.call(
          key: "node_pair:#{request.remote_ip}",
          limit: 10,
          window: 1.minute
        )
        if rate_result.failure?
          return render json: { error: I18n.t("mcweb.user_copy.too_many_pairing_attempts") }, status: :too_many_requests
        end

        result = Minecraft::PairNode.call(
          token: params[:pairing_token] || params[:token],
          hostname: params[:hostname]
        )

        if result.success?
          render json: result.value
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end
    end
  end
end
