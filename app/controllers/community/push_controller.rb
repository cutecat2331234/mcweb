# frozen_string_literal: true

module Community
  # Web Push subscription endpoints.
  class PushController < ApplicationController
    before_action :require_login, except: %i[public_key]

    def public_key
      render json: { public_key: Community::VapidKeys.public_key }
    end

    def subscribe
      subscription = params.require(:subscription)
      keys = subscription[:keys] || {}

      record = Community::PushSubscription.find_or_initialize_by(endpoint: subscription[:endpoint].to_s)
      record.user = current_user
      record.p256dh_key = keys[:p256dh].to_s
      record.auth_key = keys[:auth].to_s

      if record.save
        head :ok
      else
        head :unprocessable_entity
      end
    end

    def unsubscribe
      Community::PushSubscription.where(user: current_user, endpoint: params[:endpoint].to_s).destroy_all
      head :ok
    end
  end
end
