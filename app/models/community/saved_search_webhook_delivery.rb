# frozen_string_literal: true

module Community
  class SavedSearchWebhookDelivery < ApplicationRecord
    self.table_name = "forum_saved_search_webhook_deliveries"

    belongs_to :saved_search, class_name: "Community::SavedSearch", optional: true

    scope :recent, -> { order(created_at: :desc) }
  end
end
