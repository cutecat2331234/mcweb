# frozen_string_literal: true

module TouchLastSeen
  extend ActiveSupport::Concern

  included do
    before_action :touch_last_seen, if: :logged_in?
  end

  private

  def touch_last_seen
    return if current_user.last_seen_at && current_user.last_seen_at > 2.minutes.ago

    current_user.update_column(:last_seen_at, Time.current)
  end
end
