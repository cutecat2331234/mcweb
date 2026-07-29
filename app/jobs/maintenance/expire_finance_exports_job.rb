# frozen_string_literal: true

module Maintenance
  class ExpireFinanceExportsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Commerce::FinanceExport.completed.where("expires_at <= ?", Time.current).find_each do |finance_export|
        Commerce::ExpireFinanceExport.call(finance_export:)
      end
    end
  end
end
