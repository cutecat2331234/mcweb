# frozen_string_literal: true

module Commerce
  class ClaimGiftCard < ApplicationService
    def initialize(user:, gift_card:)
      @user = user
      @gift_card = gift_card
    end

    def call
      return ServiceResult.failure(error: "gift_card_unavailable") unless @gift_card
      return ServiceResult.failure(error: "gift_card_unavailable") if @gift_card.inapplicable_reason

      Commerce::GiftCard.transaction do
        @gift_card.lock!
        if @gift_card.owner_user_id.present? && @gift_card.owner_user_id != @user.id
          return ServiceResult.failure(error: "gift_card_unavailable")
        end

        if @gift_card.owner_user_id.blank?
          @gift_card.update!(owner_user_id: @user.id)
        end
      end

      ServiceResult.success(@gift_card.reload)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
