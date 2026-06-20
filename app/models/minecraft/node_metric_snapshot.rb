# frozen_string_literal: true

module Minecraft
  class NodeMetricSnapshot < ApplicationRecord
    belongs_to :node, class_name: "Minecraft::Node", foreign_key: :minecraft_node_id
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id, optional: true

    scope :recent, ->(duration = 24.hours) { where("recorded_at >= ?", duration.ago).order(:recorded_at) }
  end
end
