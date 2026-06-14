# frozen_string_literal: true

module Website
  class ArticlesController < ApplicationController
    def index
      @articles = Website::Article.published.order(published_at: :desc)
      @articles = @articles.by_type(params[:type]) if params[:type].present?
    end

    def show
      @article = Website::Article.published.find_by!(slug: params[:id])
    end
  end
end
