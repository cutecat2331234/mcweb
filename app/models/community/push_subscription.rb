# frozen_string_literal: true

module Community
  # A browser Web Push subscription (endpoint + keys) for a user.
  class PushSubscription < ApplicationRecord
    self.table_name = "community_push_subscriptions"

    belongs_to :user

    validates :endpoint, presence: true, uniqueness: true
    validates :p256dh_key, :auth_key, presence: true
  end
end
