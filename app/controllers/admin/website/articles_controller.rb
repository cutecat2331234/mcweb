# frozen_string_literal: true

module Admin
  module Website
    class ArticlesController < BaseController
      include NestedLocaleParams

      before_action -> { require_permission("website.articles.read") }
      before_action -> { require_permission("website.articles.edit") },
                    only: %i[new create edit update discard_form discard archive]
      before_action -> { require_permission("website.articles.publish") }, only: %i[publish schedule archive]
      before_action :set_article,
                    only: %i[show edit update discard_form discard publish schedule archive preview]

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
              type: article_type_label(article.article_type),
              status: content_status_label(article.status),
              published: article.published_at ? l(article.published_at, format: :short) : "—",
              url: admin_website_article_path(article)
            )
          end,
          actions: index_actions
        }
      end

      def show
        render inertia: "Admin/Generic/Show", props: {
          title: @article.title,
          subtitle: @article.slug,
          fields: [
            { label: t("mcweb.admin.website.articles.col_type"), value: article_type_label(@article.article_type) },
            { label: t("mcweb.admin.common.status"), value: content_status_label(@article.status) },
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
        result = ::Website::ContentUpdate.call(
          content: @article,
          attributes: article_params.except(:lock_version),
          actor: current_user,
          expected_lock_version: article_params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_article_path(@article), notice: t("mcweb.flash.updated", resource: t("mcweb.resources.article"))
        else
          redirect_to edit_admin_website_article_path(@article), alert: service_error_message(result)
        end
      end

      def discard_form
        render inertia: "Admin/Website/ContentDiscard", props: {
          title: t("mcweb.admin.website.recovery.discard_title"),
          content: {
            type: "article", title: @article.title, slug: @article.slug,
            lock_version: @article.lock_version
          },
          submitUrl: discard_admin_website_article_path(@article),
          backUrl: admin_website_article_path(@article),
          replacementRequired: false,
          replacementOptions: []
        }
      end

      def discard
        result = ::Website::DiscardContent.call(
          content: @article,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_recycle_bin_path,
                      notice: t("mcweb.admin.website.recovery.discarded")
        else
          redirect_to discard_form_admin_website_article_path(@article),
                      alert: service_error_message(result)
        end
      end

      def publish
        result = ::Website::ArticlePublisher.call(
          article: @article,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
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

        result = ::Website::ArticlePublisher.call(
          article: @article,
          publish_at: publish_at,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_article_path(@article), notice: t("mcweb.admin.website.scheduled", default: "Scheduled")
        else
          redirect_to admin_website_article_path(@article), alert: service_error_message(result)
        end
      end

      def archive
        result = ::Website::ArchiveContent.call(
          content: @article,
          actor: current_user,
          expected_lock_version: params[:lock_version],
          request_id: params[:request_id]
        )
        if result.success?
          redirect_to admin_website_article_path(@article),
                      notice: t("mcweb.admin.website.recovery.archived")
        else
          redirect_to admin_website_article_path(@article), alert: service_error_message(result)
        end
      end

      def preview
        body_result = ::Website::RenderArticleBody.call(body: @article.body)
        seo_result = ::Website::ResolveSeo.call(record: @article)

        ::Frontend::WebsiteRenderer.preview(
          controller: self,
          component: "Website/Articles/Show",
          props: {
          article: serialize_article_detail(@article).merge(
            body_html: body_result.success? ? body_result.value.to_s : "",
            slug: @article.slug
          ),
          seo: seo_result.value,
          preview_context: {
            return_url: admin_website_article_path(@article),
            edit_url: edit_admin_website_article_path(@article),
            label: @article.title,
            mode_label: t("mcweb.admin.website.preview", default: "Preview")
          }
          }
        )
      end

      private

      def set_article
        scope = action_name == "discard" ? ::Website::Article.with_lifecycle : ::Website::Article.all
        @article = scope.find_by!(public_id: params[:id])
      end

      def article_params
        permitted = params.require(:article).permit(
          :title, :slug, :article_type, :summary, :body, :lock_version,
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
            translations: article.translations.presence || {},
            lock_version: article.lock_version
          },
          articleTypeOptions: %w[news blog].map { |value| { value:, label: article_type_label(value) } },
          statusOptions: ::Website::Article.statuses.keys.map { |value| { value:, label: content_status_label(value) } },
          locales: %w[en zh-CN],
          submitUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          publishUrl: article.persisted? ? publish_admin_website_article_path(article) : nil,
          scheduleUrl: article.persisted? ? schedule_admin_website_article_path(article) : nil,
          previewUrl: article.persisted? ? preview_admin_website_article_path(article) : nil,
          revisionsUrl: article.persisted? ? admin_website_article_revisions_path(article) : nil,
          method: article.persisted? ? "patch" : "post",
          backUrl: article.persisted? ? admin_website_article_path(article) : admin_website_articles_path,
          form_errors: article.errors.to_hash(true),
          canPublish: current_user.permission?("website.articles.publish")
        }
      end

      def show_actions
        actions = [
          { label: t("mcweb.admin.website.preview", default: "Preview"), href: preview_admin_website_article_path(@article), hardNavigation: true },
          { label: t("mcweb.admin.website.revisions.title"), href: admin_website_article_revisions_path(@article) }
        ]
        if current_user.permission?("website.articles.edit")
          actions.unshift(label: t("mcweb.admin.ui.edit"), href: edit_admin_website_article_path(@article))
        end
        if current_user.permission?("website.articles.publish")
          actions << {
            label: t("mcweb.admin.website.publish", default: "Publish"),
            href: publish_admin_website_article_path(@article), method: "post",
            data: { lock_version: @article.lock_version, request_id: "website-publish-article-#{SecureRandom.uuid}" }
          }
        end
        if current_user.permission?("website.articles.edit") &&
            current_user.permission?("website.articles.publish")
          actions << {
            label: t("mcweb.admin.website.recovery.archive"),
            href: archive_admin_website_article_path(@article), method: "post",
            data: { lock_version: @article.lock_version, request_id: "website-archive-article-#{SecureRandom.uuid}" },
            confirm: t("mcweb.admin.website.recovery.archive_confirm")
          }
        end
        if current_user.permission?("website.articles.edit")
          actions << {
            label: t("mcweb.admin.website.recovery.discard"),
            href: discard_form_admin_website_article_path(@article)
          }
        end
        actions
      end

      def article_type_label(value)
        t("mcweb.admin.website.articles.types.#{value}")
      end

      def content_status_label(value)
        t("mcweb.admin.website.statuses.#{value}")
      end

      def index_actions
        actions = []
        if current_user.permission?("website.articles.edit")
          actions << { label: t("mcweb.admin.website.articles.new"), href: new_admin_website_article_path }
        end
        if current_user.permission?("website.content.restore") ||
            current_user.permission?("website.content.purge")
          actions << { label: t("mcweb.admin.website.recovery.title"), href: admin_website_recycle_bin_path }
        end
        actions
      end
    end
  end
end
