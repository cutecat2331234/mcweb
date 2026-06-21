# frozen_string_literal: true

module Admin
  module Website
    class ArticlesController < BaseController
      include NestedLocaleParams

      before_action -> { require_permission("website.articles.read") }, only: %i[index show preview]
      before_action -> { require_permission("website.articles.edit") }, only: %i[new create edit update destroy]
      before_action -> { require_permission("website.articles.publish") }, only: %i[publish schedule]
      before_action :set_article, only: %i[show edit update destroy publish schedule preview]

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
          actions: show_actions
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

      def publish
        result = ::Website::ArticlePublisher.call(article: @article, actor: current_user)
        if result.success?
          redirect_to admin_website_article_path(@article), notice: t("mcweb.admin.website.published", default: "Published")
        else
          redirect_to admin_website_article_path(@article), alert: service_error_message(result)
        end
      end

      def schedule
        publish_at = parse_schedule_time(params[:publish_at])
        unless publish_at&.future?
          redirect_to admin_website_article_path(@article),
                      alert: t("mcweb.admin.website.invalid_schedule", default: "Choose a future publish date and time")
          return
        end

        result = ::Website::ArticlePublisher.call(article: @article, publish_at: publish_at, actor: current_user)
        if result.success?
          redirect_to admin_website_article_path(@article), notice: t("mcweb.admin.website.scheduled", default: "Scheduled")
        else
          redirect_to admin_website_article_path(@article), alert: service_error_message(result)
        end
      end

      def preview
        body_result = ::Website::RenderArticleBody.call(body: @article.body)
        seo_result = ::Website::ResolveSeo.call(record: @article)

        render inertia: "Website/Articles/Show", props: {
          article: serialize_article_detail(@article).merge(
            body_html: body_result.success? ? body_result.value.to_s : "",
            slug: @article.slug
          ),
          seo: seo_result.value
        }
      end

      private

      def set_article
        @article = ::Website::Article.find_by!(public_id: params[:id])
      end

      def article_params
        permitted = params.require(:article).permit(
          :title, :slug, :article_type, :summary, :body,
          seo: {}
        )
        permitted[:seo] = permitted[:seo].to_unsafe_h if permitted[:seo].is_a?(ActionController::Parameters)
        merge_nested_translations!(permitted, :article)
        permitted
      end

      def parse_schedule_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
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
            body: article.body,
            published_at: article.published_at&.strftime("%Y-%m-%dT%H:%M"),
            scheduled_at: article.scheduled_at&.strftime("%Y-%m-%dT%H:%M"),
            seo: article.seo.presence || { "title" => "", "description" => "", "og_image" => "" },
            translations: article.translations.presence || {}
          },
          articleTypeOptions: %w[news blog].map { |value| { value:, label: value } },
          statusOptions: ::Website::Article.statuses.keys.map { |value| { value:, label: value } },
          locales: %w[en zh-CN],
          submitUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          publishUrl: article.persisted? ? publish_admin_website_article_path(article) : nil,
          scheduleUrl: article.persisted? ? schedule_admin_website_article_path(article) : nil,
          previewUrl: article.persisted? ? preview_admin_website_article_path(article) : nil,
          method: article.persisted? ? "patch" : "post",
          backUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          form_errors: article.errors.to_hash(true),
          canPublish: current_user.permission?("website.articles.publish")
        }
      end

      def show_actions
        actions = [
          { label: t("mcweb.admin.ui.edit"), href: edit_admin_website_article_path(@article) },
          { label: t("mcweb.admin.website.preview", default: "Preview"), href: preview_admin_website_article_path(@article), external: true }
        ]
        if current_user.permission?("website.articles.publish")
          actions << { label: t("mcweb.admin.website.publish", default: "Publish"), href: publish_admin_website_article_path(@article), method: "post" }
        end
        if current_user.permission?("website.articles.edit")
          actions << { label: t("mcweb.admin.ui.delete", default: "Delete"), href: admin_website_article_path(@article), method: "delete", confirm: t("mcweb.admin.website.confirm_delete", default: "Delete this article?") }
        end
        actions
      end
    end
  end
end
