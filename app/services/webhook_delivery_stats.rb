# frozen_string_literal: true

class WebhookDeliveryStats
  WINDOW = 24.hours

  def self.summary
    new.summary
  end

  def summary
    {
      forum: stats_for(Community::SavedSearchWebhookDelivery),
      store: stats_for(Commerce::OrderWebhookDelivery),
      store_by_event: store_stats_by_event
    }
  end

private

  def stats_for(model)
    scope = model.where(created_at: WINDOW.ago..)
    total = scope.count
    success = scope.where(status: "success").count
    failed = scope.where(status: "failed").count
    pending = scope.where(status: "pending").count
    {
      total: total,
      success: success,
      failed: failed,
      pending: pending,
      success_rate: total.positive? ? ((success.to_f / total) * 100).round(1) : nil
    }
  end

  def store_stats_by_event
    scope = Commerce::OrderWebhookDelivery.where(created_at: WINDOW.ago..)
    Commerce::DispatchTestOrderWebhook::EVENT_TYPES.map do |event_type|
      event_scope = scope.where(event_type: event_type)
      total = event_scope.count
      success = event_scope.where(status: "success").count
      failed = event_scope.where(status: "failed").count
      {
        event_type: event_type,
        total: total,
        success: success,
        failed: failed,
        success_rate: total.positive? ? ((success.to_f / total) * 100).round(1) : nil
      }
    end
  end
end
