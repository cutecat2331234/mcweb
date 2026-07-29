# frozen_string_literal: true

module Maintenance
  class ExpireDataExportsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Identity::DataExport.completed.where("expires_at <= ?", Time.current).find_each do |data_export|
        data_export.mark_expired_if_needed!
      end
    end
  end
end
