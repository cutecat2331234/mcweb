# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      scope = Commerce::Product.includes(:category).available
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("name ILIKE ? OR slug ILIKE ?", q, q)
      end
      scope = case params[:sort]
              when "price_asc" then scope.order(price_cents: :asc)
              when "price_desc" then scope.order(price_cents: :desc)
              when "popular" then scope.order(view_count: :desc, created_at: :desc)
              when "rating" then scope.left_joins(:reviews).where(store_reviews: { status: "published" })
                .group("store_products.id").order(Arel.sql("COALESCE(AVG(store_reviews.rating), 0) DESC"))
              else scope.order(created_at: :desc)
              end

      if params[:category].present?
        category = Commerce::Category.find_by!(slug: params[:category])
        scope = scope.where(store_category_id: category.id)
      end

      featured = Commerce::Product.available.where(featured: true).order(created_at: :desc).limit(6)

      @pagy, products = pagy(scope, limit: 20)
      categories = Commerce::Category.ordered

      render inertia: "Commerce/Products/Index", props: {
        products: products.map { |product| serialize_product_list_item(product) },
        featured_products: featured.map { |product| serialize_product_list_item(product) },
        categories: categories.map { |category| serialize_category(category) },
        activeCategory: params[:category],
        query: params[:q].to_s,
        sort: params[:sort].to_s.presence || "newest",
        pagination: pagy_props(@pagy)
      }
    end

    def show
      product = Commerce::Product.available.includes(:variants, :category).find_by!(public_id: params[:id])
      product.increment!(:view_count)
      reviews = product.reviews.published.includes(:user).order(created_at: :desc).limit(20)
      avg = product.reviews.published.average(:rating)&.round(1)
      wishlisted = logged_in? && Commerce::WishlistItem.exists?(user: current_user, product: product)
      stock_alert_variant_ids = if logged_in?
                                Commerce::StockAlert.where(user: current_user, product: product).pluck(:store_product_variant_id)
                              else
                                []
                              end
      can_review = logged_in? && Commerce::CreateReview.purchased?(user: current_user, product: product)
      related = if product.store_category_id
                  product.category.products.available.where.not(id: product.id).order(created_at: :desc).limit(4)
                else
                  Commerce::Product.none
                end

      questions = product.questions.visible.includes(:user, :answers).recent.limit(20)

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product, wishlisted: wishlisted, reviews: reviews, average_rating: avg),
        related_products: related.map { |p| serialize_product_list_item(p) },
        questions: questions.map { |q| serialize_product_question(q) },
        stockAlertUrl: stock_alert_store_product_path(product),
        stockAlertVariantIds: stock_alert_variant_ids,
        canReview: can_review,
        addToCartUrl: store_cart_path,
        wishlistUrl: wishlist_store_product_path(product),
        reviewUrl: store_reviews_path(product),
        questionUrl: store_questions_path(product),
        canAnswerOfficially: logged_in? && (current_user.permission?("store.questions.answer") || current_user.permission?("admin.access")),
        loggedIn: logged_in?
      }
    end

    private

    def serialize_product_question(question)
      {
        id: question.id,
        body: question.body,
        author: question.user.username,
        created_at: l(question.created_at, format: :short),
        answerUrl: answer_question_store_product_path(question.product, question_id: question.id),
        answers: question.answers.order(created_at: :asc).map do |answer|
          {
            id: answer.id,
            body: answer.body,
            author: answer.user.username,
            official: answer.official,
            created_at: l(answer.created_at, format: :short)
          }
        end
      }
    end
  end
end
