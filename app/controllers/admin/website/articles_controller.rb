# frozen_string_literal: true

module Admin
  module Website
    class ArticlesController < BaseController
      before_action -> { require_permission("website.pages.edit") }
      before_action :set_article, only: %i[show edit update destroy]

      def index
        articles = ::Website::Article.order(updated_at: :desc)

        render inertia: "Admin/Generic/Index", props: {
          title: t("mcweb.admin.website.articles.title"),
          columns: [
            admin_column(:title, t("mcweb.admin.website.articles.col_title"), link: true),
            admin_column(:type, t("mcweb.admin.website.articles.col_type")),
            admin_column(:status, t("mcweb.admin.common.status")),
            admin_column(:published, t("mcweb.admin.website.articles.col_published"))
          ],
          rows: articles.map do |article|
            admin_row(
              title: article.title,
              type: article.article_type,
              status: article.status,
              published: article.published_at ? l(article.published_at, format: :short) : "—",
              url: admin_website_article_path(article)
            )
          end,
          actions: [ { label: t("mcweb.admin.website.articles.new"), href: new_admin_website_article_path } ]
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @article.title,
          subtitle: @article.slug,
          fields: [
            { label: t("mcweb.admin.website.articles.col_type"), value: @article.article_type },
            { label: t("mcweb.admin.common.status"), value: @article.status },
            { label: t("mcweb.admin.website.articles.field_summary"), value: @article.summary.presence || "—" },
            { label: t("mcweb.admin.website.articles.col_published"), value: @article.published_at ? l(@article.published_at, format: :long) : "—" }
          ],
          backUrl: admin_website_articles_path,
          actions: [ { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_article_path(@article) } ]
        }
      end

      def new
        render inertia: "Admin/Website/Articles/Form", props: form_props(::Website::Article.new)
      end

      def create
        article = ::Website::Article.new(article_params)
        article.author = current_user

        if article.save
          redirect_to admin_website_article_path(article), notice: t("mcweb.flash.created", resource: t("mcweb.resources.article"))
        else
          render inertia: "Admin/Website/Articles/Form", props: form_props(article), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Website/Articles/Form", props: form_props(@article)
      end

      def update
        if @article.update(article_params)
          redirect_to admin_website_article_path(@article), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.article"))
        else
          render inertia: "Admin/Website/Articles/Form", props: form_props(@article), status: :unprocessable_entity
        end
      end

      def destroy
        @article.destroy!
        redirect_to admin_website_articles_path, notice: t("mcweb.flash.deleted", resource: t("mcweb.resources.article"))
      end

      private

      def set_article
        @article = ::Website::Article.find_by!(public_id: params[:id])
      end

      def article_params
        params.require(:article).permit(:title, :slug, :article_type, :status, :summary, :published_at)
      end

      def form_props(article)
        {
          title: article.persisted? ? t("mcweb.admin.website.articles.edit") : t("mcweb.admin.website.articles.new"),
          article: {
            title: article.title,
            slug: article.slug,
            article_type: article.article_type.presence || "news",
            status: article.status.presence || "draft",
            summary: article.summary,
            published_at: article.published_at&.strftime("%Y-%m-%dT%H:%M")
          },
          articleTypeOptions: %w[news blog].map { |value| { value:, label: value } },
          statusOptions: ::Website::Article.statuses.keys.map { |value| { value:, label: value } },
          submitUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          method: article.persisted? ? "patch" : "post",
          backUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          form_errors: article.errors.to_hash(true)
        }
      end
    end
  end
end
