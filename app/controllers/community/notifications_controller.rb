# frozen_string_literal: true

module Community
  # Compatibility endpoint for links created before notifications moved from
  # the forum namespace into the account application.
  class NotificationsController < ::Account::NotificationsController
    def index
      redirect_to account_notifications_path(notification_index_query_params), status: :found
    end
  end
end
