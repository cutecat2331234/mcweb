# frozen_string_literal: true

module Commerce
  class ReviewsController < ApplicationController
    before_action :require_login
    before_action :set_visible_product, only: %i[create toggle_helpful share_to_forum]
    before_action :set_mutation_product, only: %i[update destroy]
    before_action :set_review, only: %i[toggle_helpful share_to_forum]
    before_action :set_owned_review, only: %i[update destroy]

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

    def update
      result = Commerce::UpdateReview.call(
        user: current_user,
        review: @review,
        rating: review_params[:rating],
        expected_version: review_params[:expected_version],
        body: review_params[:body],
        retained_photo_ids: review_params[:retained_photo_ids],
        photo_selection_present: review_params[:photo_selection_present],
        photos: review_params[:photos]
      )

      if result.success?
        redirect_to review_return_path, notice: t("mcweb.flash.review_updated")
      else
        redirect_to review_return_path, alert: service_error_message(result)
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
        redirect_to review_return_path, notice: t("mcweb.flash.review_deleted")
      else
        redirect_to review_return_path, alert: service_error_message(result)
      end
    end

    private

    def set_visible_product
      @product = Commerce::Product.available.find_by!(public_id: params[:product_id])
      raise ActiveRecord::RecordNotFound unless Commerce::StoreFeatures.product_visible?(@product)
    end

    def set_mutation_product
      @product = Commerce::Product.find_by!(public_id: params[:product_id])
    end

    def set_review
      @review = @product.reviews.find(params[:id])
    end

    def set_owned_review
      @review = @product.reviews.where(user: current_user).find(params[:id])
    end

    def review_params
      params.require(:review).permit(
        :rating,
        :body,
        :expected_version,
        :photo_selection_present,
        photos: [],
        retained_photo_ids: []
      )
    end

    def review_return_path
      if Commerce::Product.available.where(id: @product.id).exists? &&
          Commerce::StoreFeatures.product_visible?(@product)
        store_product_path(@product)
      else
        store_products_path
      end
    end
  end
end
