# frozen_string_literal: true

module Maintenance
  class CleanupExpiredLinkCodesJob < ApplicationJob
    queue_as :maintenance

    def perform
      Minecraft::LinkCode
        .where(used_at: nil)
        .where("expires_at < ?", Time.current)
        .delete_all

      Minecraft::LinkCode
        .where.not(used_at: nil)
        .where("created_at < ?", 7.days.ago)
        .delete_all
    end
  end
end
