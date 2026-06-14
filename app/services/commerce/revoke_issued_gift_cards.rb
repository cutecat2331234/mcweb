# frozen_string_literal: true

module Commerce
  class RevokeIssuedGiftCards < ApplicationService
    def initialize(order:)
      @order = order
    end

    def call
      item_ids = @order.items.pluck(:id)
      cards = Commerce::GiftCard.where(source_order_item_id: item_ids, active: true)
      return ServiceResult.success(revoked: 0) if cards.empty?

      revoked = 0
      cards.find_each do |card|
        next unless card.active?

        balance = card.balance_cents
        card.update!(active: false, balance_cents: 0, note: [ card.note, "订单 #{@order.order_number} 退款撤销" ].compact.join(" · "))
        Commerce::RecordGiftCardTransaction.call(
          gift_card: card,
          amount_cents: -balance,
          transaction_type: "revoke",
          order: @order
        )
        revoked += 1
      end

      ServiceResult.success(revoked: revoked)
    end
  end
end
