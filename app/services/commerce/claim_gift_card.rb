# frozen_string_literal: true

module Commerce
  class ClaimGiftCard < ApplicationService
    def initialize(user:, gift_card:)
      @user = user
      @gift_card = gift_card
    end

    def call
      return ServiceResult.failure(error: "礼品卡无效。") unless @gift_card
      return ServiceResult.failure(error: @gift_card.inapplicable_reason) if @gift_card.inapplicable_reason

      if @gift_card.owner_user_id.present? && @gift_card.owner_user_id != @user.id
        return ServiceResult.failure(error: "此礼品卡已绑定其他账户。")
      end

      @gift_card.update!(owner_user_id: @user.id) if @gift_card.owner_user_id.blank?
      ServiceResult.success(@gift_card)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
