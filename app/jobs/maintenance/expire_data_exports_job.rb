# frozen_string_literal: true

module Maintenance
  class ExpireDataExportsJob < ApplicationJob
    queue_as :maintenance

    def perform
      now = Time.current
      Identity::DataExport.completed.where("expires_at <= ?", now).find_each do |data_export|
        data_export.mark_expired_if_needed!(at: now)
      end
    end
  end
end
