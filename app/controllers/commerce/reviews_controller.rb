# frozen_string_literal: true

module Commerce
  class ReviewsController < ApplicationController
    before_action :require_login
    before_action :set_product, only: %i[create destroy toggle_helpful share_to_forum]
    before_action :set_review, only: %i[destroy toggle_helpful share_to_forum]

    def create
      result = Commerce::CreateReview.call(
        user: current_user,
        product: @product,
        rating: review_params[:rating],
        body: review_params[:body],
        photos: review_params[:photos]
      )

      if result.success?
        redirect_to store_product_path(@product), notice: t("mcweb.flash.review_submitted")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def share_to_forum
      result = Commerce::ShareReviewToForum.call(user: current_user, review: @review)

      if result.success?
        redirect_to forum_topic_path(result.value[:topic]), notice: t("mcweb.flash.review_shared")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def toggle_helpful
      result = Commerce::ToggleReviewHelpful.call(user: current_user, review: @review)

      if result.success?
        redirect_to store_product_path(@product), notice: result.value[:helpful] ? t("mcweb.flash.helpful_marked") : t("mcweb.flash.helpful_unmarked")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    def destroy
      result = Commerce::DeleteReview.call(user: current_user, review: @review)

      if result.success?
        redirect_to store_product_path(@product), notice: t("mcweb.flash.review_deleted")
      else
        redirect_to store_product_path(@product), alert: service_error_message(result)
      end
    end

    private

    def set_product
      @product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      raise ActiveRecord::RecordNotFound unless Commerce::StoreFeatures.product_visible?(@product)
    end

    def set_review
      @review = @product.reviews.find(params[:id])
    end

    def review_params
      params.require(:review).permit(:rating, :body, photos: [])
    end
  end
end
