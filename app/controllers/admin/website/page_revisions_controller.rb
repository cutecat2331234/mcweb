# frozen_string_literal: true

module Admin
  module Website
    class PageRevisionsController < BaseController
      before_action -> { require_permission("website.pages.read") }, only: %i[index show]
      before_action -> { require_permission("website.pages.edit") }, only: %i[restore_draft]
      before_action :set_page
      before_action :set_revision, only: %i[show restore_draft]

      def index
        revisions = @page.revisions.ordered.includes(:author)

        render inertia: "Admin/Website/Pages/Revisions/Index", props: {
          title: t("mcweb.admin.website.revisions.title", default: "Revisions"),
          page: { id: @page.public_id, title: @page.title },
          revisions: revisions.map { |revision| serialize_revision(revision) },
          backUrl: admin_website_page_path(@page)
        }
      end

      def show
        render inertia: "Admin/Website/Pages/Revisions/Show", props: {
          title: t("mcweb.admin.website.revisions.show", default: "Revision"),
          page: { id: @page.public_id, title: @page.title },
          revision: serialize_revision(@revision).merge(
            snapshot: @revision.snapshot,
            restoreUrl: restore_draft_admin_website_page_revision_path(@page, @revision)
          ),
          backUrl: admin_website_page_revisions_path(@page)
        }
      end

      def restore_draft
        snapshot = @revision.snapshot
        draft = ::Website::Page.new(
          title: snapshot["title"],
          slug: "#{snapshot['slug']}-restored-#{SecureRandom.hex(3)}",
          page_type: snapshot["page_type"] || "custom",
          status: "draft",
          seo: snapshot["seo"] || {},
          translations: snapshot["translations"] || {},
          author: current_user
        )
        draft.save!
        Array(snapshot["blocks"]).each do |block_data|
          draft.blocks.create!(
            block_type: block_data["block_type"],
            position: block_data["position"],
            settings: block_data["settings"] || {},
            translations: block_data["translations"] || {},
            visible: block_data.fetch("visible", true)
          )
        end
        redirect_to edit_admin_website_page_path(draft), notice: t("mcweb.admin.website.revisions.restored", default: "Draft page created from revision")
      end

      private

      def set_page
        @page = ::Website::Page.find_by!(public_id: params[:page_id])
      end

      def set_revision
        @revision = @page.revisions.find(params[:id])
      end

      def serialize_revision(revision)
        {
          id: revision.id,
          revision_number: revision.revision_number,
          author: revision.author&.username,
          created_at: l(revision.created_at, format: :long),
          url: admin_website_page_revision_path(@page, revision)
        }
      end
    end
  end
end
