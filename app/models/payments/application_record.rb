module Payments
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true

    def self.table_name_prefix
      "payment_"
    end
  end
end
