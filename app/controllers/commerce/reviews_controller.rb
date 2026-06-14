# frozen_string_literal: true

module Commerce
  class ReviewsController < ApplicationController
    before_action :require_login
    before_action :set_product, only: %i[create toggle_helpful]
    before_action :set_review, only: %i[toggle_helpful]

    def create
      result = Commerce::CreateReview.call(
        user: current_user,
        product: @product,
        rating: review_params[:rating],
        body: review_params[:body]
      )

      if result.success?
        redirect_to store_product_path(@product), notice: "评价已提交。"
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def toggle_helpful
      result = Commerce::ToggleReviewHelpful.call(user: current_user, review: @review)

      if result.success?
        redirect_to store_product_path(@product), notice: result.value[:helpful] ? "已标记为有帮助。" : "已取消标记。"
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    private

    def set_product
      @product = Commerce::Product.find_by!(public_id: params[:product_id])
    end

    def set_review
      @review = @product.reviews.find(params[:id])
    end

    def review_params
      params.require(:review).permit(:rating, :body)
    end
  end
end
