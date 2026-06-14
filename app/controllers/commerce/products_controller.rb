# frozen_string_literal: true

module Commerce
  class ProductsController < ApplicationController
    def index
      scope = Commerce::Product.includes(:category).available
      scope = scope.with_stock if params[:in_stock] == "1"
      scope = scope.on_sale if params[:on_sale] == "1"
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
        scope = scope.where("name ILIKE ? OR slug ILIKE ?", q, q)
      end
      scope = case params[:sort]
              when "price_asc" then scope.order(price_cents: :asc)
              when "price_desc" then scope.order(price_cents: :desc)
              when "discount_desc" then scope.on_sale.order(Arel.sql("((compare_at_price_cents - price_cents)::float / NULLIF(compare_at_price_cents, 0)) DESC"))
              when "popular" then scope.order(view_count: :desc, created_at: :desc)
              when "rating" then scope.left_joins(:reviews).where(store_reviews: { status: "published" })
                .group("store_products.id").order(Arel.sql("COALESCE(AVG(store_reviews.rating), 0) DESC"))
              else scope.order(created_at: :desc)
              end

      if params[:category].present?
        category = Commerce::Category.find_by!(slug: params[:category])
        scope = scope.where(store_category_id: category.id)
      end

      if params[:price_min].present?
        min_cents = (params[:price_min].to_f * 100).to_i
        scope = scope.where("price_cents >= ?", min_cents) if min_cents.positive?
      end
      if params[:price_max].present?
        max_cents = (params[:price_max].to_f * 100).to_i
        scope = scope.where("price_cents <= ?", max_cents) if max_cents.positive?
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
        onSale: params[:on_sale] == "1",
        priceMin: params[:price_min].to_s,
        priceMax: params[:price_max].to_s,
        compareCount: compare_product_count,
        pagination: pagy_props(@pagy)
      }
    end

    def recently_viewed
      return redirect_to store_products_path, alert: "请先登录。" unless logged_in?

      products = Commerce::ProductView.recent_for(current_user)
        .includes(:product)
        .limit(20)
        .filter_map { |view| view.product if view.product&.active? }

      render inertia: "Commerce/RecentlyViewed/Index", props: {
        products: products.map { |product| serialize_product_list_item(product) },
        clearUrl: clear_recently_viewed_store_products_path
      }
    end

    def clear_recently_viewed
      return redirect_to store_products_path, alert: "请先登录。" unless logged_in?

      Commerce::ProductView.where(user: current_user).delete_all
      redirect_to recently_viewed_store_products_path, notice: "浏览记录已清空。"
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
      rating_breakdown = product.reviews.published.group(:rating).count
      wishlist_item = logged_in? ? Commerce::WishlistItem.find_by(user: current_user, product: product) : nil
      wishlisted = wishlist_item.present?
      compared = Array(session[:compare_product_ids]).include?(product.public_id)
      stock_alerts = if logged_in?
                       Commerce::StockAlert.where(user: current_user, product: product).index_by(&:store_product_variant_id)
                     else
                       {}
                     end
      stock_alert_variant_ids = stock_alerts.keys
      user_review = logged_in? ? product.reviews.published.find_by(user: current_user) : nil
      purchased = logged_in? && Commerce::CreateReview.purchased?(user: current_user, product: product)
      can_review = logged_in? && purchased && user_review.nil?
      can_edit_review = logged_in? && purchased && user_review.present?
      can_delete_review = logged_in? && user_review.present? && user_review.user_id == current_user.id
      related = if product.store_category_id
                  product.category.products.available.where.not(id: product.id).order(created_at: :desc).limit(4)
                else
                  Commerce::Product.none
                end

      questions_scope = product.questions.visible.includes(:user, :answers).recent
      if params[:question_q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:question_q].to_s.strip)}%"
        questions_scope = questions_scope.where("body ILIKE ?", q)
      end
      question_page = [ params[:question_page].to_i, 1 ].max
      @pagy_questions, questions = pagy(questions_scope, limit: 10, page: question_page)

      render inertia: "Commerce/Products/Show", props: {
        product: serialize_product_detail(product, wishlisted: wishlisted, reviews: reviews, average_rating: avg).merge(
          saved_variant_id: wishlist_item&.variant_id,
          purchased: purchased
        ),
        reviewsCount: reviews_count,
        ratingBreakdown: (1..5).map { |rating| { rating: rating, count: rating_breakdown[rating] || 0 } },
        reviewsPagination: pagy_props(@pagy_reviews),
        related_products: related.map { |p| serialize_product_list_item(p) },
        questions: questions.map { |q| serialize_product_question(q) },
        questionsPagination: pagy_props(@pagy_questions),
        questionQuery: params[:question_q].to_s,
        stockAlertUrl: stock_alert_store_product_path(product),
        stockAlertVariantIds: stock_alert_variant_ids,
        canReview: can_review,
        canEditReview: can_edit_review,
        canDeleteReview: can_delete_review,
        deleteReviewUrl: can_delete_review ? store_product_review_path(product, user_review) : nil,
        userReview: user_review ? serialize_review(user_review, current_user: current_user) : nil,
        reviewSort: review_sort.presence || "newest",
        reviewRating: (1..5).cover?(review_rating) ? review_rating : nil,
        addToCartUrl: store_cart_path,
        wishlistUrl: wishlist_store_product_path(product),
        compareUrl: store_toggle_compare_path(product_id: product.public_id),
        compared: compared,
        compareCount: compare_product_count,
        stockAlertUnsubscribeUrls: stock_alerts.map do |variant_id, alert|
          { variant_id: variant_id, unsubscribe_url: store_stock_alert_path(alert) }
        end,
        reorderUrl: logged_in? && purchased ? reorder_store_product_path(product) : nil,
        reviewUrl: store_reviews_path(product),
        questionUrl: store_questions_path(product),
        canAnswerOfficially: logged_in? && (current_user.permission?("store.questions.answer") || current_user.permission?("admin.access")),
        loggedIn: logged_in?
      }
    end

    def reorder
      return redirect_to store_products_path, alert: "请先登录。" unless logged_in?

      product = Commerce::Product.available.find_by!(public_id: params[:id])
      result = Commerce::ReorderProduct.call(user: current_user, product: product)

      if result.success?
        redirect_to store_cart_path, notice: "已加入购物车。"
      else
        redirect_to store_product_path(product), alert: service_error_message(result)
      end
    end

    private

    def index_filter_params
      {
        q: params[:q].presence,
        sort: params[:sort].presence,
        in_stock: params[:in_stock] == "1" ? "1" : nil,
        on_sale: params[:on_sale] == "1" ? "1" : nil,
        price_min: params[:price_min].presence,
        price_max: params[:price_max].presence
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
