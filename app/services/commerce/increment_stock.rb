# frozen_string_literal: true

module Commerce
  class IncrementStock < ApplicationService
    def initialize(target:, quantity:)
      @target = target
      @quantity = quantity.to_i
    end

    def call
      return ServiceResult.success if @target.stock.nil? || @quantity <= 0

      @target.with_lock do
        @target.reload
        @target.update!(stock: @target.stock + @quantity)
      end

      ServiceResult.success(@target)
    end
  end
end
