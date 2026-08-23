# frozen_string_literal: true

module Admin
  module Website
    class PageRevisionsController < BaseController
      before_action -> { require_permission("website.pages.read") }
      before_action -> { require_permission("website.pages.edit") }, only: %i[restore_draft]
      before_action -> { require_permission("website.content.restore") }, only: %i[restore_draft]
      before_action :set_page
      before_action :set_revision, only: %i[show restore_draft]

      def index
        render inertia: "Admin/Website/Revisions/Index", props: {
          title: t("mcweb.admin.website.revisions.title"),
          content: content_props,
          revisions: @page.revisions.ordered.includes(:author).map { |revision| serialize_revision(revision) },
          backUrl: content_back_url
        }
      end

      def show
        render inertia: "Admin/Website/Revisions/Show", props: {
          title: t("mcweb.admin.website.revisions.show"),
          content: content_props,
          revision: serialize_revision(@revision).merge(
            snapshot: @revision.snapshot,
            restoreUrl: restore_draft_admin_website_page_revision_path(@page, @revision)
          ),
          canRestore: current_user.permission?("website.pages.edit") &&
            current_user.permission?("website.content.restore") && !@page.purged?,
          backUrl: admin_website_page_revisions_path(@page)
        }
      end

      def restore_draft
        result = ::Website::RestoreRevision.call(
          content: @page,
          revision: @revision,
          actor: current_user,
          reason: params[:reason],
          confirmation: params[:confirmation],
          expected_lock_version: params[:lock_version],
          idempotency_key: params[:request_id]
        )
        if result.success?
          redirect_to edit_admin_website_page_path(@page),
                      notice: t("mcweb.admin.website.revisions.restored")
        else
          redirect_to admin_website_page_revision_path(@page, @revision),
                      alert: service_error_message(result)
        end
      end

      private

      def set_page
        @page = ::Website::Page.with_lifecycle.find_by!(public_id: params[:page_id])
      end

      def set_revision
        @revision = @page.revisions.find(params[:id])
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
          url: admin_website_page_revision_path(@page, revision)
        }
      end

      def content_props
        {
          id: @page.public_id,
          type: "page",
          title: @page.title,
          slug: @page.slug,
          status: @page.purged? ? "purged" : @page.status,
          lock_version: @page.lock_version
        }
      end

      def content_back_url
        if current_user.permission?("website.content.restore") ||
            current_user.permission?("website.content.purge")
          return admin_website_recycle_bin_item_path("page", @page.public_id) if @page.discarded?
          return admin_website_recycle_bin_path if @page.purged?
        end
        return admin_website_pages_path if @page.discarded? || @page.purged?

        admin_website_page_path(@page)
      end
    end
  end
end
