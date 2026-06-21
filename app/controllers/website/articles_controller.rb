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
      body_result = Website::RenderArticleBody.call(body: article.body)
      seo_result = Website::ResolveSeo.call(record: article)

      render inertia: "Website/Articles/Show", props: {
        article: serialize_article_detail(article).merge(
          body_html: body_result.success? ? body_result.value.to_s : "",
          slug: article.slug
        ),
        seo: seo_result.value
      }
    end
  end
end
