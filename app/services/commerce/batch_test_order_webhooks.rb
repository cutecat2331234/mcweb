# frozen_string_literal: true

module Commerce
  class BatchTestOrderWebhooks < ApplicationService
    def call
      queued = 0
      Commerce::DispatchTestOrderWebhook::EVENT_TYPES.each do |event_type|
        result = Commerce::DispatchTestOrderWebhook.call(event_type: event_type)
        queued += 1 if result.success?
      end

      ServiceResult.success(
        queued: queued,
        total: Commerce::DispatchTestOrderWebhook::EVENT_TYPES.size
      )
    end
  end
end
