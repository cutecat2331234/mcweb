# frozen_string_literal: true

module Community
  class FetchCouponOnebox < ApplicationService
    def initialize(url:)
      @url = url.to_s.strip
    end

    def call
      # Coupon codes and discount details must not be exposed in public post oneboxes.
      ServiceResult.success(nil)
    end
  end
end
