# frozen_string_literal: true

module Commerce
  class ReviewsController < ApplicationController
    before_action :require_login

    def create
      product = Commerce::Product.find_by!(public_id: params[:product_id])
      result = Commerce::CreateReview.call(
        user: current_user,
        product: product,
        rating: review_params[:rating],
        body: review_params[:body]
      )

      if result.success?
        redirect_to store_product_path(product), notice: "评价已提交。"
      else
        redirect_to store_product_path(product), alert: service_error_message(result)
      end
    end

    private

    def review_params
      params.require(:review).permit(:rating, :body)
    end
  end
end
