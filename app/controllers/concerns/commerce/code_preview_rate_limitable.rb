# frozen_string_literal: true

module Commerce
  module CodePreviewRateLimitable
    extend ActiveSupport::Concern

    private

    def preview_rate_limited?
      actor_key = respond_to?(:current_user, true) && current_user ? current_user.id : "anon"
      Administration::RateLimiter.call(
        key: "cart_code_preview:#{request.remote_ip}:#{actor_key}",
        limit: 30,
        window: 15.minutes
      ).failure?
    end

    def render_preview_rate_limited
      render json: { error: t("mcweb.flash.rate_limited", default: "操作过于频繁，请稍后再试。") }, status: :too_many_requests
    end

    def apply_code_rate_limited?
      actor_key = respond_to?(:current_user, true) && current_user ? current_user.id : "anon"
      Administration::RateLimiter.call(
        key: "cart_code_apply:#{request.remote_ip}:#{actor_key}",
        limit: 30,
        window: 15.minutes
      ).failure?
    end
  end
end
