# frozen_string_literal: true

module Admin
  module Website
    class ArticleRevisionsController < BaseController
      before_action -> { require_permission("website.articles.read") }
      before_action -> { require_permission("website.articles.edit") }, only: %i[restore_draft]
      before_action -> { require_permission("website.content.restore") }, only: %i[restore_draft]
      before_action :set_article
      before_action :set_revision, only: %i[show restore_draft]

      def index
        render inertia: "Admin/Website/Revisions/Index", props: {
          title: t("mcweb.admin.website.revisions.title"),
          content: content_props,
          revisions: @article.revisions.ordered.includes(:author).map { |revision| serialize_revision(revision) },
          backUrl: content_back_url
        }
      end

      def show
        render inertia: "Admin/Website/Revisions/Show", props: {
          title: t("mcweb.admin.website.revisions.show"),
          content: content_props,
          revision: serialize_revision(@revision).merge(
            snapshot: @revision.snapshot,
            restoreUrl: restore_draft_admin_website_article_revision_path(@article, @revision)
          ),
          canRestore: current_user.permission?("website.articles.edit") &&
            current_user.permission?("website.content.restore") && !@article.purged?,
          backUrl: admin_website_article_revisions_path(@article)
        }
      end

      def restore_draft
        result = ::Website::RestoreRevision.call(
          content: @article,
          revision: @revision,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id]
        )
        if result.success?
          redirect_to edit_admin_website_article_path(@article),
                      notice: t("mcweb.admin.website.revisions.restored")
        else
          redirect_to admin_website_article_revision_path(@article, @revision),
                      alert: service_error_message(result)
        end
      end

      private

      def set_article
        @article = ::Website::Article.with_lifecycle.find_by!(public_id: params[:article_id])
      end

      def set_revision
        @revision = @article.revisions.find(params[:id])
      end

      def serialize_revision(revision)
        {
          id: revision.id,
          revision_number: revision.revision_number,
          event_type: revision.event_type,
          reason: revision.reason,
          source_lock_version: revision.source_lock_version,
          author: revision.author&.username,
          created_at: l(revision.created_at, format: :long),
          url: admin_website_article_revision_path(@article, revision)
        }
      end

      def content_props
        {
          id: @article.public_id,
          type: "article",
          title: @article.title,
          slug: @article.slug,
          status: @article.purged? ? "purged" : @article.status,
          lock_version: @article.lock_version
        }
      end

      def content_back_url
        return admin_website_recycle_bin_item_path("article", @article.public_id) if @article.discarded?
        return admin_website_recycle_bin_path if @article.purged?

        admin_website_article_path(@article)
      end
    end
  end
end
