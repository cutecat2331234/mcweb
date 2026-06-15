# frozen_string_literal: true

module Community
  class FetchGiftCardOnebox < ApplicationService
    GIFT_CARD_PATH = %r{\A/store/gift_cards/([\w-]+)\z}i

    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      path = if @url.start_with?("/")
               @url
      else
               URI.parse(@url).path
      end
      return ServiceResult.success(nil) unless path

      match = path.match(GIFT_CARD_PATH)
      return ServiceResult.success(nil) unless match

      card = Commerce::GiftCard.find_by(code: match[1].upcase)
      return ServiceResult.success(nil) unless card

      ServiceResult.success(
        code: card.code,
        balance_label: format_money(card.balance_cents, card.currency),
        redeemable: card.redeemable?,
        url: "/store/gift_cards/#{card.code}"
      )
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end

    private

    def format_money(cents, currency)
      unit = currency == "CNY" ? "¥" : "$"
      ActionController::Base.helpers.number_to_currency(cents / 100.0, unit: unit)
    end
  end
end
