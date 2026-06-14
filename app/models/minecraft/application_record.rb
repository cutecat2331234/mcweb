module Minecraft
  class ApplicationRecord < ::ApplicationRecord
    self.abstract_class = true

    def self.table_name_prefix
      "minecraft_"
    end
  end
end
