# frozen_string_literal: true

module Website
  class HomeController < ApplicationController
    skip_installation_guard only: :index

    def index
      featured = begin
        Website::Article.published.order(published_at: :desc).limit(6)
      rescue ActiveRecord::StatementInvalid
        []
      end

      render inertia: "Website/Home", props: {
        featuredArticles: featured.map { |article| serialize_article(article) }
      }
    end
  end
end
