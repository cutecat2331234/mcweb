# frozen_string_literal: true

module Community
  # Per-user real-time notification stream (XenForo-style live alerts).
  class NotificationsChannel < ApplicationCable::Channel
    def subscribed
      stream_for current_user
    end
  end
end
