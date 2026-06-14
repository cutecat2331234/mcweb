# frozen_string_literal: true

module Commerce
  class CreateProductQuestion < ApplicationService
    def initialize(user:, product:, body:, order_item: nil)
      @user = user
      @product = product
      @body = body.to_s.strip
      @order_item = order_item
    end

    def call
      return ServiceResult.failure(error: "Question is required.") if @body.blank?

      if @order_item
        return ServiceResult.failure(error: "订单商品不匹配。") unless @order_item.store_product_id == @product.id
        return ServiceResult.failure(error: "无权就此订单提问。") unless @order_item.order.user_id == @user.id
      end

      question = Commerce::ProductQuestion.create!(
        user: @user,
        product: @product,
        body: @body,
        order_item: @order_item,
        status: "published"
      )
      Commerce::NotifyNewProductQuestion.call(question: question)
      ServiceResult.success(question)
    rescue ActiveRecord::RecordInvalid => e
      ServiceResult.failure(errors: e.record.errors.to_hash)
    end
  end
end
