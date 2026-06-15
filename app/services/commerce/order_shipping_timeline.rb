# frozen_string_literal: true

module Commerce
  class OrderShippingTimeline
    STEPS = [
      { key: "placed", label: "订单已提交" },
      { key: "paid", label: "已支付" },
      { key: "shipped", label: "已发货" },
      { key: "in_transit", label: "运输中" },
      { key: "delivered", label: "已送达" }
    ].freeze

    def self.call(order)
      new(order).steps
    end

    def initialize(order)
      @order = order
    end

    def steps
      return [] unless show_timeline?

      timestamps = {
        "placed" => @order.created_at,
        "paid" => paid_at,
        "shipped" => @order.shipped_at,
        "in_transit" => in_transit_at,
        "delivered" => delivered_at
      }

      last_done_index = STEPS.rindex { |step| timestamps[step[:key]].present? }

      STEPS.map.with_index do |step, index|
        at = timestamps[step[:key]]
        state = if at.present?
                  "done"
        elsif last_done_index.nil? && index.zero?
                  "current"
        elsif last_done_index && index == last_done_index + 1
                  "current"
        else
                  "pending"
        end

        { key: step[:key], label: step[:label], at: at, state: state }
      end
    end

  private

    def show_timeline?
      physical_order? || @order.shipped_at.present? || @order.tracking_number.present?
    end

    def physical_order?
      @order.items.any? do |item|
        snapshot = item.fulfillment_snapshot || {}
        snapshot["product_type"].to_s == "physical" || snapshot[:product_type].to_s == "physical"
      end
    end

    def paid_at
      if @order.total_cents.zero? && !%w[pending awaiting_payment cancelled failed].include?(@order.status)
        return @order.created_at
      end

      event_at = @order.events.where(event_type: %w[paid payment_confirmed mark_paid]).order(:created_at).first&.created_at
      return event_at if event_at.present?

      return @order.updated_at if @order.status.in?(%w[paid processing fulfilling fulfilled completed])

      nil
    end

    def in_transit_at
      return nil if @order.shipped_at.blank?
      return @order.shipped_at if @order.status.in?(%w[processing fulfilling fulfilled completed])

      nil
    end

    def delivered_at
      return @order.shipped_at if @order.status.in?(%w[fulfilled completed]) && @order.shipped_at.present?

      @order.events.where(event_type: %w[fulfilled shipped]).order(created_at: :desc).first&.created_at if @order.status.in?(%w[fulfilled completed])
    end
  end
end
