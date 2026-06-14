module Community
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true

    def self.table_name_prefix
      "forum_"
    end
  end
end
