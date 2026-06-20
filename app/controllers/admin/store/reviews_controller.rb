# frozen_string_literal: true

module Admin
  module Store
    class ReviewsController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_review, only: %i[show update]

      def index
        reviews = ::Commerce::Review.includes(:user, :product).order(created_at: :desc).limit(100)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.store.reviews.title"),
          columns: [
            admin_column(:product, t("mcweb.admin.store.reviews.col_product"), link: true),
            admin_column(:author, t("mcweb.admin.store.reviews.col_author")),
            admin_column(:rating, t("mcweb.admin.store.reviews.col_rating")),
            admin_column(:status, t("mcweb.admin.store.reviews.col_status"))
          ],
          rows: reviews.map do |review|
            admin_row(
              product: review.product.name,
              author: review.user.username,
              rating: "#{review.rating}★",
              status: review_status_label(review.status),
              url: admin_store_review_path(review)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: t("mcweb.admin.store.reviews.show_title", product: @review.product.name),
          fields: [
            { label: t("mcweb.admin.store.reviews.field_user"), value: @review.user.username },
            { label: t("mcweb.admin.store.reviews.field_rating"), value: "#{@review.rating}★" },
            { label: t("mcweb.admin.store.reviews.field_status"), value: review_status_label(@review.status) },
            { label: t("mcweb.admin.store.reviews.field_body"), value: @review.body || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.reviews.field_merchant_reply"), value: @review.merchant_reply || t("mcweb.labels.not_available") },
            { label: t("mcweb.admin.store.reviews.field_time"), value: l(@review.created_at, format: :long) }
          ],
          backUrl: admin_store_reviews_path,
          actions: review_actions
        }
      end

      def update
        if review_params[:merchant_reply].present?
          result = Commerce::ReplyToReview.call(
            review: @review,
            actor: current_user,
            body: review_params[:merchant_reply]
          )
          return redirect_to admin_store_review_path(@review), notice: t("mcweb.flash.merchant_reply_published") if result.success?

          return redirect_to admin_store_review_path(@review), alert: service_error_message(result)
        end

        status = review_params[:status]
        if status.present? && @review.update(status: status)
          redirect_to admin_store_reviews_path, notice: t("mcweb.flash.review_updated")
        else
          redirect_to admin_store_reviews_path, alert: @review.errors.full_messages.to_sentence
        end
      end

      private

      def set_review
        @review = ::Commerce::Review.find(params[:id])
      end

      def review_params
        params.fetch(:review, {}).permit(:status, :merchant_reply)
      end

      def review_actions
        actions = []
        if @review.published?
          actions << {
            label: t("mcweb.admin.store.reviews.action_hide"),
            href: admin_store_review_path(@review),
            method: "patch",
            data: { review: { status: "hidden" } }
          }
        elsif @review.hidden?
          actions << {
            label: t("mcweb.admin.store.reviews.action_show"),
            href: admin_store_review_path(@review),
            method: "patch",
            data: { review: { status: "published" } }
          }
        end
        actions
      end
    end
  end
end
