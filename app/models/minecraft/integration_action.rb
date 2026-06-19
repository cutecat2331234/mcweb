# frozen_string_literal: true

module Minecraft
  class IntegrationAction < ApplicationRecord
    has_many :action_logs, class_name: "Minecraft::IntegrationActionLog", foreign_key: :integration_action_id, dependent: :destroy

    validates :name, :event_key, presence: true

    scope :enabled, -> { where(enabled: true) }
    scope :for_event, ->(event_key) { enabled.where(event_key: event_key).order(priority: :desc) }
  end
end
