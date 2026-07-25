# frozen_string_literal: true

module Community
  class UnpinExpiredTopicsJob < ApplicationJob
    queue_as :maintenance

    def perform
      Community::Topic
        .where(pinned: true)
        .where("pinned_until IS NOT NULL AND pinned_until <= ?", Time.current)
        .find_each do |topic|
          actor = Community::SystemActor.user || topic.user
          action_result = nil
          Community::Topic.transaction do
            topic.update!(pinned: false, pinned_until: nil)
            if actor
              action_result = Community::CreateSmallActionPost.call(
                topic: topic,
                actor: actor,
                body: "置顶时间已到，已自动取消置顶。"
              )
              raise ActiveRecord::Rollback if action_result.failure?
            end
          end
          next if action_result&.failure?
        end
    end
  end
end
