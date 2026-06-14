# frozen_string_literal: true

module Website
  class ArticlesController < ApplicationController
    def index
      articles = Website::Article.published.order(published_at: :desc)
      articles = articles.by_type(params[:type]) if params[:type].present?

      render inertia: "Website/Articles/Index", props: {
        articles: articles.map { |article| serialize_article(article) }
      }
    end

    def show
      article = Website::Article.published.find_by!(slug: params[:id])

      render inertia: "Website/Articles/Show", props: {
        article: serialize_article_detail(article)
      }
    end
  end
end
