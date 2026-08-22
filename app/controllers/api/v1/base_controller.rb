# frozen_string_literal: true

module Api
  module V1
    # Base controller for the public REST API (v1). Stateless: authenticated with
    # an API key via `Authorization: Bearer <token>` or the `X-Api-Key` header.
    # Content is scoped to what the key's associated user (or an anonymous guest,
    # when the key has no user) is allowed to see.
    class BaseController < ActionController::API
      include Pagy::Method
      include ServiceResponder

      before_action :authenticate_api_key!
      before_action :rate_limit!
      before_action :require_read_scope!

      rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

      private

      attr_reader :current_api_key

      def authenticate_api_key!
        @current_api_key = Administration::ApiKey.authenticate(bearer_token)
        return if @current_api_key

        render_error("invalid_api_key", status: :unauthorized)
      end

      # Rendering filter: halts the action when the key lacks the read scope.
      def require_read_scope!
        require_scope!("read")
      end

      def require_scope!(scope)
        return true if current_api_key&.allows?(scope)

        render_error("insufficient_scope", status: :forbidden, extra: { required: scope })
        false
      end

      # Write actions: require the write scope AND an acting user (mutations are
      # always performed as a specific user so the domain services can enforce
      # permissions, trust levels, and rate limits).
      def require_writer!
        return render_error("insufficient_scope", status: :forbidden, extra: { required: "write" }) unless current_api_key&.allows?("write")
        return if api_user

        render_error("write_requires_user", status: :forbidden)
      end

      def render_service_error(result)
        if result.rate_limited?
          apply_retry_after_header(result)
          return render(
            json: { error: "rate_limited", message: service_error_message(result) },
            status: :too_many_requests
          )
        end

        if result.code&.to_sym == :conflict
          return render(
            json: { error: result.code.to_s, message: service_error_message(result) },
            status: :conflict
          )
        end

        render json: { error: "unprocessable", message: service_error_message(result) }, status: :unprocessable_entity
      end

      # Guard for endpoints that operate on the key's own user (e.g. notifications).
      def require_bound_user!
        return if api_user

        render_error("no_bound_user", status: :forbidden)
      end

      # The user the key acts as, or nil for an anonymous/guest reader.
      def api_user
        current_api_key&.user
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        return Regexp.last_match(1) if header =~ /\ABearer\s+(.+)\z/i

        request.headers["X-Api-Key"].to_s.presence
      end

      def rate_limit!
        return unless current_api_key

        result = Administration::RateLimiter.call(
          key: "api:#{current_api_key.id}",
          limit: api_rate_limit,
          window: 1.minute
        )
        return if result.success?

        render_service_error(result)
      end

      def api_rate_limit
        SiteSetting.get("api.rate_limit_per_minute", "120").to_i.clamp(1, 100_000)
      end

      def api_paginate(scope)
        limit = params[:limit].to_i
        limit = 25 if limit <= 0
        limit = [ limit, 100 ].min
        page = [ params[:page].to_i, 1 ].max
        pagy(:offset, scope, limit: limit, page: page)
      end

      def pagination_meta(pagy)
        {
          page: pagy.page,
          pages: pagy.pages,
          count: pagy.count,
          limit: pagy.limit,
          prev: pagy.previous,
          next: pagy.next
        }
      end

      def render_not_found
        render_error("not_found", status: :not_found)
      end

      def render_error(code, status:, extra: {})
        render json: { error: code }.merge(extra), status: status
      end
    end
  end
end
