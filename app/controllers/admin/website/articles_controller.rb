# frozen_string_literal: true

module Admin
  module Website
    class ArticlesController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_article, only: %i[show edit update destroy]

      def index
        @articles = ::Website::Article.order(updated_at: :desc)
      end

      def show
      end

      def new
        @article = ::Website::Article.new
      end

      def create
        @article = ::Website::Article.new(article_params)
        @article.author = current_user

        if @article.save
          redirect_to admin_website_article_path(@article), notice: "Article created."
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @article.update(article_params)
          redirect_to admin_website_article_path(@article), notice: "Article updated."
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @article.destroy!
        redirect_to admin_website_articles_path, notice: "Article deleted."
      end

      private

      def set_article
        @article = ::Website::Article.find_by!(public_id: params[:id])
      end

      def article_params
        params.expect(article: %i[title slug article_type status body excerpt seo translations])[:article]
      end
    end
  end
end
