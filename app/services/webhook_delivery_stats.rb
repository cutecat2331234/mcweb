# frozen_string_literal: true

class WebhookDeliveryStats
  WINDOW = 24.hours

  def self.summary
    new.summary
  end

  def summary
    {
      forum: stats_for(Community::SavedSearchWebhookDelivery),
      store: stats_for(Commerce::OrderWebhookDelivery)
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
end
