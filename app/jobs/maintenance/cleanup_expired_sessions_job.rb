# frozen_string_literal: true

module Maintenance
  class CleanupExpiredSessionsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Session.where(revoked_at: nil)
        .where("expires_at < ?", Time.current)
        .find_each do |session|
          session.update!(revoked_at: Time.current)
        end

      Session.where("expires_at < ?", 30.days.ago).delete_all
    end
  end
end
