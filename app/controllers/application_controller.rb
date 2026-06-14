class ApplicationController < ActionController::Base
  include Authentication
  include InstallationGuard
  include ServiceResponder
  include Pagy::Backend
  include InertiaSerializable
  include BlockedUsersFilterable

  allow_browser versions: :modern

  stale_when_importmap_changes

  inertia_config layout: "inertia"

  inertia_share do
    share = {
      auth: {
        user: inertia_user
      },
      flash: {
        notice: flash[:notice],
        alert: flash[:alert]
      }
    }

    cart = if logged_in?
             Commerce::Cart.find_by(user: current_user)
           else
             token = cookies.signed[:cart_token]
             Commerce::Cart.find_by(session_token: token) if token.present?
           end

    if cart
      share[:cart] = {
        count: cart.items.sum(:quantity),
        url: store_cart_path
      }
    end

    if logged_in?
      share[:notifications] = {
        unread_count: current_user.notifications.unread.count,
        url: forum_notifications_path
      }
      share[:forum_unread] = {
        count: Community::ReadState.with_unread_for(current_user).count,
        url: forum_unread_path
      }
    end

    share
  end
end
