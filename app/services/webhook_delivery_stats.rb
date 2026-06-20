# frozen_string_literal: true

class WebhookDeliveryStats
  WINDOW = 24.hours

  def self.summary
    new.summary
  end

  def summary
    {
      forum: combined_forum_stats,
      store: stats_for(Commerce::OrderWebhookDelivery),
      store_by_event: store_stats_by_event,
      forum_by_event: forum_stats_by_event
    }
  end

  def combined_forum_stats
    saved = stats_hash(Community::SavedSearchWebhookDelivery.where(created_at: WINDOW.ago..))
    event = stats_hash(Community::EventWebhookDelivery.where(created_at: WINDOW.ago..))
    total = saved[:total] + event[:total]
    success = saved[:success] + event[:success]
  {
      total: total,
      success: success,
      failed: saved[:failed] + event[:failed],
      pending: saved[:pending] + event[:pending],
      success_rate: total.positive? ? ((success.to_f / total) * 100).round(1) : nil
    }
  end

private

  def stats_for(model)
    stats_hash(model.where(created_at: WINDOW.ago..))
  end

  def stats_hash(scope)
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

  def forum_stats_by_event
    scope = Community::EventWebhookDelivery.where(created_at: WINDOW.ago..)
    Community::DispatchForumEventWebhook::EVENT_TYPES.map do |event_type|
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
