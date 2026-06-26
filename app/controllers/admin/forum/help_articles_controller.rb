# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style help center article management.
    class HelpArticlesController < BaseController
      before_action -> { require_permission("forum.sections.manage") }
      before_action :set_article, only: %i[edit update destroy]

      def index
        articles = ::Community::HelpArticle.ordered

        render inertia: "Admin/Generic/Index", props: {
          title: forum_t("help_articles.title"),
          subtitle: forum_t("help_articles.description"),
          columns: [
            admin_column(:title, forum_t("help_articles.col_title"), link: true),
            admin_column(:category, forum_t("help_articles.col_category")),
            admin_column(:published, forum_t("help_articles.col_published"))
          ],
          rows: articles.map do |article|
            admin_row(
              title: article.title,
              category: article.category,
              published: forum_yes_no(article.published),
              url: edit_admin_forum_help_article_path(article)
            )
          end,
          actions: [ { label: forum_t("help_articles.action_new"), href: new_admin_forum_help_article_path } ]
        }
      end

      def new
        render inertia: "Admin/Forum/HelpArticles/Form", props: form_props(::Community::HelpArticle.new)
      end

      def create
        article = ::Community::HelpArticle.new(article_params)
        if article.save
          redirect_to admin_forum_help_articles_path, notice: t("mcweb.flash.help_article_created")
        else
          render inertia: "Admin/Forum/HelpArticles/Form", props: form_props(article), status: :unprocessable_entity
        end
      end

      def edit
        render inertia: "Admin/Forum/HelpArticles/Form", props: form_props(@article, editing: true)
      end

      def update
        if @article.update(article_params)
          redirect_to admin_forum_help_articles_path, notice: t("mcweb.flash.help_article_updated")
        else
          render inertia: "Admin/Forum/HelpArticles/Form", props: form_props(@article, editing: true), status: :unprocessable_entity
        end
      end

      def destroy
        @article.destroy!
        redirect_to admin_forum_help_articles_path, notice: t("mcweb.flash.help_article_deleted")
      end

      private

      def set_article
        @article = ::Community::HelpArticle.find(params[:id])
      end

      def article_params
        params.require(:help_article).permit(:title, :slug, :category, :body, :position, :published)
      end

      def form_props(article, editing: false)
        {
          title: editing ? forum_t("help_articles.form_edit") : forum_t("help_articles.form_new"),
          help_article: {
            title: article.title || "",
            slug: article.slug || "",
            category: article.category || "general",
            body: article.body || "",
            position: article.position || 0,
            published: article.published.nil? ? true : article.published
          },
          submitUrl: editing ? admin_forum_help_article_path(article) : admin_forum_help_articles_path,
          method: editing ? "patch" : "post",
          backUrl: admin_forum_help_articles_path,
          deleteUrl: editing ? admin_forum_help_article_path(article) : nil
        }
      end
    end
  end
end
