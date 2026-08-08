# frozen_string_literal: true

module TouchLastSeen
  extend ActiveSupport::Concern
  LAST_SEEN_TOUCH_INTERVAL = 2.minutes

  included do
    before_action :touch_last_seen, if: :logged_in?
  end

  private

  def touch_last_seen
    now = Time.current
    cutoff = now - LAST_SEEN_TOUCH_INTERVAL
    return if current_user.last_seen_at && current_user.last_seen_at > cutoff

    updated = User
      .where(id: current_user.id)
      .where("last_seen_at IS NULL OR last_seen_at <= ?", cutoff)
      .update_all(last_seen_at: now)
    current_user.last_seen_at = now if updated.positive?
  end
end
