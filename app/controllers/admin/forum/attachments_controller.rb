# frozen_string_literal: true

module Admin
  module Forum
    # XenForo-style attachment management: browse + prune orphaned uploads.
    class AttachmentsController < BaseController
      before_action -> { require_permission("forum.sections.manage") }

      def index
        filter = params[:filter].to_s
        scope = ::Community::PostAttachment.includes(:user, :post).order(created_at: :desc)
        scope = scope.unlinked if filter == "orphans"

        @pagy, attachments = pagy(:offset, scope, limit: 30)

        render inertia: "Admin/Forum/Attachments/Index", props: {
          attachments: attachments.map { |attachment| serialize_attachment(attachment) },
          pagination: pagy_props(@pagy),
          filter: filter,
          orphanCount: ::Community::PostAttachment.unlinked.count,
          pruneUrl: prune_orphans_admin_forum_attachments_path
        }
      end

      def destroy
        attachment = ::Community::PostAttachment.find(params[:id])
        attachment.destroy!
        redirect_back fallback_location: admin_forum_attachments_path, notice: t("mcweb.flash.attachment_deleted")
      end

      def prune_orphans
        count = ::Community::PostAttachment.unlinked.count
        ::Community::PostAttachment.unlinked.find_each(&:destroy!)
        redirect_to admin_forum_attachments_path, notice: t("mcweb.flash.attachments_pruned", count: count)
      end

      private

      def serialize_attachment(attachment)
        {
          id: attachment.id,
          filename: attachment.filename,
          size: attachment.human_size,
          content_type: attachment.content_type,
          downloads: attachment.download_count,
          uploader: attachment.user&.username,
          linked: attachment.linked?,
          post_url: attachment.post ? forum_topic_path(attachment.post.topic) : nil,
          created_at: l(attachment.created_at, format: :short),
          delete_url: admin_forum_attachment_path(attachment)
        }
      end
    end
  end
end
