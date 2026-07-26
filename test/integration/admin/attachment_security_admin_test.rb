# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class AttachmentSecurityAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "forum.sections.manage")
        sign_in_as(@admin)

        SiteSetting.set("forum.upload_quota.site.bytes", 10.megabytes.to_s)
        SiteSetting.set("forum.upload_quota.site.count", "321")
        SiteSetting.set("forum.upload_quota.site.hourly_count", "45")
      end

      test "authorized admin sees safe lifecycle queues and site quota usage" do
        secret = "scanner-private-path-C:/sensitive/quarantine"
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          scan_error_message: secret
        )
        create_upload(
          status: "cleanup_failed",
          scan_status: "error",
          cleanup_error_code: "StorageFailure",
          cleanup_error_message: secret
        )

        get admin_forum_attachments_path, params: { filter: "quarantined" }

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal "Admin/Forum/Attachments/Index", inertia.component

        props = inertia.props.deep_symbolize_keys
        assert_equal "quarantined", props[:filter]
        row = props.fetch(:uploads).find { |item| item[:id] == upload.id }
        assert row[:quarantined]
        assert_equal "malware_detected", row[:scan_result_code]
        assert_empty row[:actions]
        refute row.key?(:scan_error_message)
        refute row.key?(:cleanup_error_message)

        assert_equal 321, props.dig(:quotaUsage, :count, :limit)
        assert_equal 45, props.dig(:quotaUsage, :hourlyCount, :limit)
        assert_equal "10 MB", props.dig(:quotaUsage, :bytes, :limitLabel)
        assert_operator props.dig(:summary, :quarantined), :>=, 1
        assert_operator props.dig(:summary, :cleanup_failed), :>=, 1
        assert_operator props.dig(:filterCounts, :quarantined), :>=, 1
        assert_operator props.dig(:filterCounts, :cleanup_failed), :>=, 1
        refute_includes props.to_json, secret
      end

      test "dedicated manager can retry failed scans and cleanup with immutable audits" do
        grant_permission(@admin, "forum.attachments.security.manage")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("safe attachment payload"),
          filename: "retry-scan.bin",
          content_type: "application/octet-stream"
        )
        scan_upload = create_upload(
          scan_status: "error",
          quarantined_at: Time.current,
          scan_result_code: "scanner_timeout",
          blob: blob
        )

        assert_enqueued_with(
          job: Community::ScanPostAttachmentJob,
          args: [ { upload_id: scan_upload.id } ]
        ) do
          assert_difference(
            -> {
              AuditLog.where(
                action: "admin.forum_attachment_scan_retried",
                resource_id: scan_upload.id
              ).count
            },
            1
          ) do
            post retry_scan_admin_forum_attachment_path(scan_upload)
          end
        end

        assert_redirected_to admin_forum_attachments_path(filter: "scan_pending")
        scan_upload.reload
        assert_predicate scan_upload, :scan_status_pending?
        assert_equal 0, scan_upload.scan_attempts
        assert_nil scan_upload.quarantined_at
        assert_operator scan_upload.expires_at, :>, 23.hours.from_now

        cleanup_upload = create_upload(
          status: "cleanup_failed",
          scan_status: "error",
          cleanup_error_code: "StorageFailure"
        )
        assert_enqueued_with(
          job: Maintenance::CleanupForumUploadsJob,
          args: [ { upload_id: cleanup_upload.id } ]
        ) do
          assert_difference(
            -> {
              AuditLog.where(
                action: "admin.forum_attachment_cleanup_retried",
                resource_id: cleanup_upload.id
              ).count
            },
            1
          ) do
            post retry_cleanup_admin_forum_attachment_path(cleanup_upload)
          end
        end

        assert_redirected_to admin_forum_attachments_path(filter: "cleanup_failed")
        assert_in_delta Time.current.to_f, cleanup_upload.reload.expires_at.to_f, 2
      end

      test "scan retry fails closed when no blob is available" do
        grant_permission(@admin, "forum.attachments.security.manage")
        upload = create_upload(
          scan_status: "error",
          quarantined_at: Time.current,
          scan_result_code: "blob_missing"
        )

        assert_no_enqueued_jobs only: Community::ScanPostAttachmentJob do
          assert_no_difference(
            -> { AuditLog.where(action: "admin.forum_attachment_scan_retried").count }
          ) do
            post retry_scan_admin_forum_attachment_path(upload)
          end
        end

        assert_redirected_to admin_forum_attachments_path
        assert_predicate upload.reload, :scan_status_error?
        assert upload.quarantined_at.present?
      end

      test "read permission cannot invoke attachment security mutations" do
        upload = create_upload(status: "cleanup_failed", scan_status: "error")

        assert_no_enqueued_jobs only: Maintenance::CleanupForumUploadsJob do
          post retry_cleanup_admin_forum_attachment_path(upload)
        end

        assert_redirected_to root_path
        assert_predicate upload.reload, :status_cleanup_failed?
      end

      test "unknown filters fall back to all uploads" do
        create_upload

        get admin_forum_attachments_path, params: { filter: "not-a-real-queue" }

        assert_response :success
        assert_equal "", inertia.props.deep_symbolize_keys[:filter]
      end

      test "admin access without forum management permission cannot inspect uploads" do
        delete identity_session_path
        limited_admin = create_user
        grant_permission(limited_admin, "admin.access")
        sign_in_as(limited_admin)

        get admin_forum_attachments_path

        assert_response :redirect
        assert_not_equal 200, response.status
      end

      private

      def create_upload(
        status: "stored",
        scan_status: "pending",
        quarantined_at: nil,
        scan_result_code: nil,
        scan_error_message: nil,
        cleanup_error_code: nil,
        cleanup_error_message: nil,
        blob: nil
      )
        Community::Upload.create!(
          user: create_user,
          public_id: Community::Upload.generate_public_id,
          kind: "post_attachment",
          status: status,
          byte_size: 1.kilobyte,
          scan_status: scan_status,
          quarantined_at: quarantined_at,
          scan_result_code: scan_result_code,
          scan_error_message: scan_error_message,
          cleanup_error_code: cleanup_error_code,
          cleanup_error_message: cleanup_error_message,
          blob: blob,
          expires_at: 1.day.from_now
        )
      end
    end
  end
end
