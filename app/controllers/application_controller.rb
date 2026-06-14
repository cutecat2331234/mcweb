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

    if logged_in?
      share[:notifications] = {
        unread_count: current_user.notifications.unread.count,
        url: forum_notifications_path
      }
    end

    share
  end
end
