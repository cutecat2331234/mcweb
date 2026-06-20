# frozen_string_literal: true

module Community
  class BatchTestForumEventWebhooks < ApplicationService
    def call
      queued = 0
      DispatchForumEventWebhook::EVENT_TYPES.each do |event_type|
        result = DispatchTestForumEventWebhook.call(event_type: event_type)
        queued += 1 if result.success?
      end
      ServiceResult.success(queued: queued, total: DispatchForumEventWebhook::EVENT_TYPES.size)
    end
  end
end
