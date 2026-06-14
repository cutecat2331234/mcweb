# frozen_string_literal: true

module Commerce
  class ClearCart < ApplicationService
    def initialize(cart:)
      @cart = cart
    end

    def call
      @cart.items.destroy_all
      @cart.reset_abandoned_reminder!
      ServiceResult.success
    end
  end
end
