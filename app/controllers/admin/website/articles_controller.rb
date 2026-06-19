# frozen_string_literal: true

module Admin
  module Website
    class ArticlesController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_article, only: %i[show edit update destroy]

      def index
        articles = ::Website::Article.order(updated_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: "官网文章",
          columns: [
            admin_column(:title, "标题", link: true),
            admin_column(:type, "类型"),
            admin_column(:status, "状态"),
            admin_column(:published, "发布")
          ],
          rows: articles.map do |article|
            admin_row(
              title: article.title,
              type: article.article_type,
              status: article.status,
              published: article.published_at ? l(article.published_at, format: :short) : "—",
              url: admin_website_article_path(article)
            )
          end
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @article.title,
          subtitle: @article.slug,
          fields: [
            { label: "类型", value: @article.article_type },
            { label: "状态", value: @article.status },
            { label: "摘要", value: @article.summary || "—" },
            { label: "发布时间", value: @article.published_at ? l(@article.published_at, format: :long) : "—" }
          ],
          backUrl: admin_website_articles_path
        }
      end

      def new
        @article = ::Website::Article.new
      end

      def create
        @article = ::Website::Article.new(article_params)

        if @article.save
          redirect_to admin_website_article_path(@article), notice: "文章已创建。"
        else
          render :new, status: :unprocessable_entity
        end
      end

      def edit
      end

      def update
        if @article.update(article_params)
          redirect_to admin_website_article_path(@article), notice: "文章已更新。"
        else
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @article.destroy!
        redirect_to admin_website_articles_path, notice: "文章已删除。"
      end

      private

      def set_article
        @article = ::Website::Article.find_by!(public_id: params[:id])
      end

      def article_params
        params.expect(article: %i[title slug article_type status summary published_at scheduled_at seo translations])[:article]
      end
    end
  end
end
