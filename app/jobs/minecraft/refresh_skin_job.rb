# frozen_string_literal: true

module Minecraft
  class RefreshSkinJob < ApplicationJob
    queue_as :minecraft

    def perform(uuid, platform: "java")
      RefreshSkin.call(uuid: uuid, platform: platform)
    end
  end
end
