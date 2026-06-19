# frozen_string_literal: true

module Admin
  module Store
    class ReviewsController < BaseController
      before_action -> { require_permission("store.products.manage") }
      before_action :set_review, only: %i[show update]

      def index
        reviews = ::Commerce::Review.includes(:user, :product).order(created_at: :desc).limit(100)

        render inertia: "Admin/Generic/Index", props: {
          title: "商品评价",
          columns: [
            admin_column(:product, "商品", link: true),
            admin_column(:author, "用户"),
            admin_column(:rating, "评分"),
            admin_column(:status, "状态")
          ],
          rows: reviews.map do |review|
            admin_row(
              product: review.product.name,
              author: review.user.username,
              rating: "#{review.rating}★",
              status: review.status,
              url: admin_store_review_path(review)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: "评价 — #{@review.product.name}",
          fields: [
            { label: "用户", value: @review.user.username },
            { label: "评分", value: "#{@review.rating}★" },
            { label: "状态", value: @review.status },
            { label: "内容", value: @review.body || "—" },
            { label: "商家回复", value: @review.merchant_reply || "—" },
            { label: "时间", value: l(@review.created_at, format: :long) }
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
          actions << { label: "隐藏评价", href: admin_store_review_path(@review), method: "patch", data: { review: { status: "hidden" } } }
        elsif @review.hidden?
          actions << { label: "显示评价", href: admin_store_review_path(@review), method: "patch", data: { review: { status: "published" } } }
        end
        actions
      end
    end
  end
end
