# frozen_string_literal: true

module Minecraft
  class ServerSnapshot < ApplicationRecord
    belongs_to :server, class_name: "Minecraft::Server", foreign_key: :minecraft_server_id

    validates :minecraft_server_id, presence: true
  end
end
