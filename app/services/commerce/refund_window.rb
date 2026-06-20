# frozen_string_literal: true

module Commerce
  module RefundWindow
    module_function

    def window_days
      SiteSetting.get("store.refund_window_days", "0").to_i
    end

    def enabled?
      window_days.positive?
    end

    def within_window?(order)
      days = window_days
      return false if days <= 0

      anchor = payment_succeeded_at(order)
      return false unless anchor

      Time.current <= anchor + days.days
    end

    def expires_at(order)
      days = window_days
      return nil if days <= 0

      anchor = payment_succeeded_at(order)
      return nil unless anchor

      anchor + days.days
    end

    def payment_succeeded_at(order)
      order.events.where(to_status: "paid").order(created_at: :desc).pick(:created_at) ||
        order.primary_succeeded_payment_record&.updated_at
    end
  end
end
