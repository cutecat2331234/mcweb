# frozen_string_literal: true

module Community
  class UnpinExpiredTopicsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Community::Topic
        .where(pinned: true)
        .where("pinned_until IS NOT NULL AND pinned_until <= ?", Time.current)
        .find_each do |topic|
          topic.update!(pinned: false, pinned_until: nil)
        end
    end
  end
end
