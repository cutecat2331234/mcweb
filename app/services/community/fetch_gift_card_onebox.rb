# frozen_string_literal: true

module Community
  class FetchGiftCardOnebox < ApplicationService
    GIFT_CARD_PATH = %r{\A(?:/app)?/store/gift_cards/([\w-]+)\z}i

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

      # Gift card codes and balances must not be exposed in public post oneboxes.
      ServiceResult.success(nil)
    rescue URI::InvalidURIError
      ServiceResult.success(nil)
    end
  end
end
