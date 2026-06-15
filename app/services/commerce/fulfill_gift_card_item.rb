# frozen_string_literal: true

module Commerce
  class FulfillGiftCardItem < ApplicationService
    def initialize(order_item:)
      @order_item = order_item
      @order = order_item.order
    end

    def call
      snapshot = @order_item.fulfillment_snapshot || {}
      product_type = snapshot["product_type"] || snapshot[:product_type]
      return ServiceResult.failure(error: "Not a gift card product.") unless product_type == "gift_card"

      cards = nil

      Commerce::OrderItem.transaction do
        @order_item.lock!

        existing_count = Commerce::GiftCard.where(source_order_item_id: @order_item.id).count
        if existing_count >= @order_item.quantity
          return ServiceResult.success(Commerce::GiftCard.where(source_order_item_id: @order_item.id).to_a)
        end

        config = snapshot["fulfillment_config"] || snapshot[:fulfillment_config] || {}
        amount_cents = @order_item.unit_price_cents
        expiry_days = config["expiry_days"].to_i

        cards = Commerce::GiftCard.where(source_order_item_id: @order_item.id).to_a
        remaining = @order_item.quantity - cards.size

        remaining.times do
          card = Commerce::GiftCard.create!(
            code: generate_code,
            balance_cents: amount_cents,
            initial_balance_cents: amount_cents,
            currency: @order.currency,
            active: true,
            owner_user_id: @order.user_id,
            created_by_id: @order.user_id,
            source_order_item_id: @order_item.id,
            expires_at: expiry_days.positive? ? expiry_days.days.from_now : nil,
            note: "订单 #{@order.order_number} 购买"
          )
          Commerce::RecordGiftCardTransaction.call(
            gift_card: card,
            amount_cents: amount_cents,
            transaction_type: "issue",
            order: @order
          )
          cards << card
        end
      end

      fulfillment = Commerce::Fulfillment.find_by(order_item: @order_item)
      unless fulfillment
        result = Commerce::CreateFulfillment.call(order_item: @order_item)
        return result if result.failure?

        fulfillment = result.value
      end

      fulfillment.mark_fulfilled! unless fulfillment.fulfilled?
      Commerce::SyncOrderFulfillmentStatus.call(order: @order)

      MailDeliveryJob.perform_later(
        "Commerce::GiftCardMailer",
        "gift_card_purchased",
        "deliver_now",
        args: [ @order.id, cards.map(&:id) ]
      )

      ServiceResult.success(cards)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end

    private

    def generate_code
      loop do
        code = "GC#{SecureRandom.alphanumeric(12).upcase}"
        break code unless Commerce::GiftCard.exists?(code: code)
      end
    end
  end
end
