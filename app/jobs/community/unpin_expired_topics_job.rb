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
          actor = Community::SystemActor.user || topic.user
          Community::CreateSmallActionPost.call(topic: topic, actor: actor, body: "置顶时间已到，已自动取消置顶。") if actor
        end
    end
  end
end
