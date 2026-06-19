# frozen_string_literal: true

module Minecraft
  class IntegrationActionLog < ApplicationRecord
    belongs_to :integration_action, class_name: "Minecraft::IntegrationAction", optional: true

    validates :event_id, :event_key, presence: true
    validates :event_id, uniqueness: true
  end
end
