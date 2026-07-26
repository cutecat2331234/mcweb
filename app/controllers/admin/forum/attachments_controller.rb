# frozen_string_literal: true

module Admin
  module Forum
    # Attachment lifecycle and security console.
    class AttachmentsController < BaseController
      FILTERS = %w[scan_pending quarantined cleanup_failed cleaned orphans].freeze
      MANAGE_PERMISSION = "forum.attachments.security.manage"

      before_action -> { require_permission("forum.sections.manage") }, only: :index
      before_action -> { require_permission(MANAGE_PERMISSION) }, except: :index

      def index
        filter = normalized_filter
        scope = filtered_uploads(filter)
          .includes(:blob, :user, post: :topic, post_attachment: { post: :topic })
          .order(created_at: :desc)

        @pagy, uploads = pagy(:offset, scope, limit: 30)
        response.headers["Cache-Control"] = "no-store"

        render inertia: "Admin/Forum/Attachments/Index", props: {
          uploads: uploads.map { |upload| serialize_upload(upload) },
          pagination: pagy_props(@pagy),
          filter: filter,
          filterCounts: filter_counts,
          summary: security_summary,
          quotaUsage: serialize_quota_usage(::Community::UploadQuota.site_usage),
          canManageSecurity: current_user.permission?(MANAGE_PERMISSION),
          orphanCount: ::Community::PostAttachment.unlinked.count,
          pruneUrl: prune_orphans_admin_forum_attachments_path
        }
      end

      def destroy
        attachment = ::Community::PostAttachment.find(params[:id])
        cleanup_attachment!(attachment)
        audit!(
          action: "admin.forum_attachment_deleted",
          resource: attachment,
          after_state: { deleted: true }
        )
        redirect_back fallback_location: admin_forum_attachments_path, notice: t("mcweb.flash.attachment_deleted")
      end

      def prune_orphans
        count = 0
        ::Community::PostAttachment.unlinked.find_each do |attachment|
          count += 1 if cleanup_orphan_attachment!(attachment)
        end
        audit!(
          action: "admin.forum_orphan_attachments_pruned",
          metadata: { count: count },
          after_state: { deleted_count: count }
        )
        redirect_to admin_forum_attachments_path, notice: t("mcweb.flash.attachments_pruned", count: count)
      end

      def retry_scan
        upload = ::Community::Upload.find(params[:id])
        result = ::Community::RetryUploadScan.call(upload: upload)
        return redirect_retry_failure("scan") if result.failure?

        value = result.value.to_h
        audit!(
          action: "admin.forum_attachment_scan_retried",
          resource: upload,
          metadata: { enqueued: value.fetch(:enqueued) },
          before_state: value.fetch(:before_state),
          after_state: { scan_status: "pending", scan_attempts: 0 }
        )
        redirect_to(
          admin_forum_attachments_path(filter: "scan_pending"),
          notice: t("mcweb.flash.attachment_scan_retry_requested")
        )
      end

      def retry_cleanup
        upload = ::Community::Upload.find(params[:id])
        result = ::Community::RetryUploadCleanup.call(upload: upload)
        return redirect_retry_failure("cleanup") if result.failure?

        audit!(
          action: "admin.forum_attachment_cleanup_retried",
          resource: upload,
          metadata: { enqueued: result.value.to_h.fetch(:enqueued) },
          before_state: {
            status: "cleanup_failed",
            cleanup_attempts: upload.cleanup_attempts
          },
          after_state: { retry_requested: true }
        )
        redirect_to(
          admin_forum_attachments_path(filter: "cleanup_failed"),
          notice: t("mcweb.flash.attachment_cleanup_retry_requested")
        )
      end

      private

      def redirect_retry_failure(kind)
        redirect_to(
          admin_forum_attachments_path,
          alert: t("mcweb.flash.attachment_#{kind}_retry_not_allowed")
        )
      end

      def audit!(action:, resource: nil, metadata: {}, before_state: {}, after_state: {})
        ::Administration::AuditLogger.call(
          actor: current_user,
          action: action,
          resource: resource,
          metadata: metadata,
          before_state: before_state,
          after_state: after_state,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end

      def normalized_filter
        value = params[:filter].to_s
        FILTERS.include?(value) ? value : ""
      end

      def filtered_uploads(filter)
        scope = ::Community::Upload.all

        case filter
        when "scan_pending"
          scope.where(scan_status: %w[pending error], quarantined_at: nil)
        when "quarantined"
          quarantined_uploads
        when "cleanup_failed"
          scope.where(status: "cleanup_failed")
        when "cleaned"
          scope.where(status: "cleaned")
        when "orphans"
          scope.where(
            forum_post_attachment_id: ::Community::PostAttachment.unlinked.select(:id)
          )
        else
          scope
        end
      end

      def quarantined_uploads
        ::Community::Upload.where(
          "scan_status = :infected OR " \
          "(scan_status = :error AND quarantined_at IS NOT NULL)",
          infected: "infected",
          error: "error"
        )
      end

      def filter_counts
        {
          all: ::Community::Upload.count,
          scan_pending: ::Community::Upload
            .where(scan_status: %w[pending error], quarantined_at: nil)
            .count,
          quarantined: quarantined_uploads.count,
          cleanup_failed: ::Community::Upload.where(status: "cleanup_failed").count,
          cleaned: ::Community::Upload.where(status: "cleaned").count,
          orphans: ::Community::PostAttachment.unlinked.count
        }
      end

      def security_summary
        active = ::Community::Upload.counted_toward_quota

        {
          active: active.count,
          scan_pending: ::Community::Upload
            .where(scan_status: %w[pending error], quarantined_at: nil)
            .count,
          quarantined: quarantined_uploads.count,
          cleanup_failed: ::Community::Upload.where(status: "cleanup_failed").count,
          cleaned: ::Community::Upload.where(status: "cleaned").count
        }
      end

      def serialize_quota_usage(usage)
        {
          bytes: {
            usedLabel: ActiveSupport::NumberHelper.number_to_human_size(
              usage.dig(:bytes, :used)
            ),
            limitLabel: usage.dig(:bytes, :limit).zero? ? nil :
              ActiveSupport::NumberHelper.number_to_human_size(usage.dig(:bytes, :limit))
          },
          count: usage.fetch(:count),
          hourlyCount: usage.fetch(:hourly_count)
        }
      end

      def cleanup_attachment!(attachment)
        upload = attachment.upload_record
        if upload
          result = ::Community::CleanupUpload.call(upload: upload, force: true)
          raise ::Maintenance::CleanupForumUploadsJob::RetryableCleanupError, result.error if result.failure?
        else
          attachment.file.purge if attachment.file.attached?
          attachment.destroy!
        end
      end

      def cleanup_orphan_attachment!(attachment)
        upload = attachment.upload_record
        if upload
          result = ::Community::CleanupUpload.call(
            upload: upload,
            orphan_only: true
          )
          if result.failure?
            raise ::Maintenance::CleanupForumUploadsJob::RetryableCleanupError,
              result.error
          end

          result.value.to_h[:cleaned] == true
        else
          destroy_unlinked_attachment!(attachment.id)
        end
      end

      def destroy_unlinked_attachment!(attachment_id)
        destroyed = false
        ::Community::PostAttachment.transaction do
          attachment = ::Community::PostAttachment.lock.find_by(id: attachment_id)
          next unless attachment && attachment.forum_post_id.nil?

          attachment.file.detach if attachment.file.attached?
          attachment.destroy!
          destroyed = true
        end
        destroyed
      end

      def serialize_upload(upload)
        attachment = upload.post_attachment
        post = upload.post || attachment&.post
        actions =
          if current_user.permission?(MANAGE_PERMISSION)
            {
              retry_scan_url: retryable_scan?(upload) ?
                retry_scan_admin_forum_attachment_path(upload) : nil,
              retry_cleanup_url: upload.status_cleanup_failed? ?
                retry_cleanup_admin_forum_attachment_path(upload) : nil
            }.compact
          else
            {}
          end

        {
          id: upload.id,
          public_id: upload.public_id,
          filename: attachment&.filename || upload.blob&.filename&.to_s || upload.public_id,
          size: ActiveSupport::NumberHelper.number_to_human_size(upload.byte_size),
          content_type: attachment&.content_type || upload.blob&.content_type,
          downloads: attachment&.download_count.to_i,
          uploader: upload.user&.username,
          kind: upload.kind,
          status: upload.status,
          scan_status: upload.scan_status,
          scan_result_code: upload.scan_result_code,
          scanner: upload.scanner,
          scan_attempts: upload.scan_attempts,
          cleanup_attempts: upload.cleanup_attempts,
          quarantined: upload.scan_quarantined?,
          linked: post.present?,
          post_url: post ? forum_topic_path(post.topic) : nil,
          created_at: upload.created_at&.iso8601,
          scanned_at: upload.scanned_at&.iso8601,
          cleaned_at: upload.cleaned_at&.iso8601,
          expires_at: upload.expires_at&.iso8601,
          delete_url: attachment && current_user.permission?(MANAGE_PERMISSION) ?
            admin_forum_attachment_path(attachment) : nil,
          actions: actions
        }
      end

      def retryable_scan?(upload)
        upload.kind_post_attachment? &&
          !upload.status_cleaned? &&
          upload.scan_status_error? &&
          upload.active_storage_blob_id.present?
      end
    end
  end
end
