# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      scope = Commerce::Product.includes(:category).available
      scope = scope.with_stock if params[:in_stock] == "1"
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

      featured_scope = Commerce::Product.available.where(featured: true)
      featured_scope = featured_scope.with_stock if params[:in_stock] == "1"
      featured = featured_scope.order(created_at: :desc).limit(6)

      recently_viewed = if logged_in?
                          Commerce::ProductView.recent_for(current_user)
                            .includes(:product)
                            .limit(6)
                            .filter_map { |view| view.product if view.product&.active? }
                        else
                          []
                        end

      @pagy, products = pagy(scope, limit: 20)
      categories = Commerce::Category.ordered
      category_query = index_filter_params

      render inertia: "Commerce/Products/Index", props: {
        products: products.map { |product| serialize_product_list_item(product) },
        featured_products: featured.map { |product| serialize_product_list_item(product) },
        recently_viewed: recently_viewed.map { |product| serialize_product_list_item(product) },
        categories: categories.map { |category| serialize_category(category, **category_query) },
        activeCategory: params[:category],
        query: params[:q].to_s,
        sort: params[:sort].to_s.presence || "newest",
        inStock: params[:in_stock] == "1",
        pagination: pagy_props(@pagy)
      }
    end

    def show
      product = Commerce::Product.available.includes(:variants, :category).find_by!(public_id: params[:id])
      product.increment!(:view_count)
      Commerce::RecordProductView.call(user: current_user, product: product) if logged_in?

      review_sort = params[:review_sort].to_s
      review_rating = params[:review_rating].to_i
      reviews_scope = product.reviews.published.includes(:user, :helpful_votes, photos_attachments: :blob)
      reviews_scope = reviews_scope.where(rating: review_rating) if (1..5).cover?(review_rating)
      reviews_scope = reviews_scope.where.not(user_id: current_user.id) if logged_in?
      reviews_scope = case review_sort
                      when "helpful"
                        reviews_scope.left_joins(:helpful_votes)
                          .group("store_reviews.id")
                          .order(Arel.sql("COUNT(store_review_helpful_votes.id) DESC, store_reviews.created_at DESC"))
                      when "rating"
                        reviews_scope.order(rating: :desc, created_at: :desc)
                      else
                        reviews_scope.order(created_at: :desc)
                      end

      review_page = [ params[:review_page].to_i, 1 ].max
      per_page = 10
      total_reviews = reviews_scope.count
      reviews = reviews_scope.limit(review_page * per_page)
      @pagy_reviews = Pagy.new(count: total_reviews, page: review_page, limit: per_page)
      reviews_count = product.reviews.published.count
      avg = product.reviews.published.average(:rating)&.round(1)
      wishlisted = logged_in? && Commerce::WishlistItem.exists?(user: current_user, product: product)
      stock_alert_variant_ids = if logged_in?
                                Commerce::StockAlert.where(user: current_user, product: product).pluck(:store_product_variant_id)
                              else
                                []
                              end
      user_review = logged_in? ? product.reviews.find_by(user: current_user) : nil
      can_review = logged_in? && Commerce::CreateReview.purchased?(user: current_user, product: product) && user_review.nil?
      related = if product.store_category_id
                  product.category.products.available.where.not(id: product.id).order(created_at: :desc).limit(4)
                else
                  Commerce::Product.none
                end

      questions = product.questions.visible.includes(:user, :answers).recent.limit(20)

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product, wishlisted: wishlisted, reviews: reviews, average_rating: avg),
        reviewsCount: reviews_count,
        reviewsPagination: pagy_props(@pagy_reviews),
        related_products: related.map { |p| serialize_product_list_item(p) },
        questions: questions.map { |q| serialize_product_question(q) },
        stockAlertUrl: stock_alert_store_product_path(product),
        stockAlertVariantIds: stock_alert_variant_ids,
        canReview: can_review,
        userReview: user_review ? serialize_review(user_review, current_user: current_user) : nil,
        reviewSort: review_sort.presence || "newest",
        reviewRating: (1..5).cover?(review_rating) ? review_rating : nil,
        addToCartUrl: store_cart_path,
        wishlistUrl: wishlist_store_product_path(product),
        reviewUrl: store_reviews_path(product),
        questionUrl: store_questions_path(product),
        canAnswerOfficially: logged_in? && (current_user.permission?("store.questions.answer") || current_user.permission?("admin.access")),
        loggedIn: logged_in?
      }
    end

    private

    def index_filter_params
      {
        q: params[:q].presence,
        sort: params[:sort].presence,
        in_stock: params[:in_stock] == "1" ? "1" : nil
      }.compact
    end

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
