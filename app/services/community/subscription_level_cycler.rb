# frozen_string_literal: true

module Community
  class SubscriptionLevelCycler
    def self.next_level(current)
      case current.to_s
      when "watching" then "tracking"
      when "tracking" then "normal"
      else nil
      end
    end
  end
end
