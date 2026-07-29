# frozen_string_literal: true

require "test_helper"
require "inertia_rails/minitest"

module Admin
  module Forum
    class AttachmentSecurityAdminTest < ActionDispatch::IntegrationTest
      setup do
        @admin = create_user
        grant_permission(@admin, "admin.access")
        grant_permission(@admin, "forum.attachments.security.read")
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

      test "dedicated release reviewer must provide exact confirmation and an audited reason" do
        grant_permission(@admin, "forum.attachments.security.release")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("independently reviewed attachment"),
          filename: "false-positive.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        get admin_forum_attachments_path, params: { filter: "quarantined" }
        row = inertia.props.deep_symbolize_keys.fetch(:uploads).find { |item| item[:id] == upload.id }
        assert_equal(
          release_quarantine_admin_forum_attachment_path(upload),
          row.dig(:actions, :release_quarantine_url)
        )
        assert_equal(
          Community::ReleaseQuarantinedUpload.confirmation_for(upload),
          row.dig(:actions, :release_confirmation)
        )

        assert_no_difference(
          -> { AuditLog.where(action: "admin.forum_attachment_quarantine_released").count }
        ) do
          post release_quarantine_admin_forum_attachment_path(upload), params: {
            reason: "Reviewed against the original scanner evidence.",
            confirmation: "RELEASE wrong-id"
          }, as: :json
        end
        assert_response :unprocessable_entity
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal(
          I18n.t("mcweb.flash.attachment_release_confirmation_mismatch"),
          JSON.parse(response.body).fetch("error")
        )
        assert_predicate upload.reload, :scan_status_infected?

        assert_difference(
          -> {
            AuditLog.where(
              action: "admin.forum_attachment_quarantine_released",
              resource_id: upload.id
            ).count
          },
          1
        ) do
          post release_quarantine_admin_forum_attachment_path(upload), params: {
            reason: "Reviewed against the original scanner evidence.",
            confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
          }, as: :json
        end

        assert_response :success
        assert_equal "no-store", response.headers["Cache-Control"]
        assert_equal true, JSON.parse(response.body).fetch("released")
        upload.reload
        assert_predicate upload, :scan_status_clean?
        assert_nil upload.quarantined_at
        assert_equal "manual_review", upload.scanner
        assert_equal "manual_false_positive", upload.scan_result_code
        assert_predicate upload, :manual_review_status_released?
        assert_equal 1, upload.manual_review_version
        assert_equal @admin.id, upload.manual_reviewed_by_id
        assert upload.manual_reviewed_at.present?
        assert_equal "malware_detected", upload.manual_review_source_result_code

        audit = AuditLog.where(
          action: "admin.forum_attachment_quarantine_released",
          resource_id: upload.id
        ).recent.first
        assert_equal "Reviewed against the original scanner evidence.", audit.reason
        assert_equal "malware_detected", audit.metadata.fetch("original_result_code")
        assert_equal Digest::SHA256.hexdigest("independently reviewed attachment"),
                     audit.metadata.fetch("file_sha256")
        assert_equal blob.checksum, audit.metadata.fetch("active_storage_checksum")
        assert_equal "text/plain", audit.metadata.fetch("inspected_content_type")
        assert_equal "infected", audit.before_state.fetch("scan_status")
        assert_equal "clean", audit.after_state.fetch("scan_status")
      end

      test "reviewer can revoke a manual release and every later download fails closed" do
        grant_permission(@admin, "forum.attachments.security.release")
        owner = create_user
        payload = "false positive later found unsafe"
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(payload),
          filename: "revocable.txt",
          content_type: "text/plain"
        )
        attachment = Community::PostAttachment.create!(
          user: owner,
          filename: "revocable.txt",
          content_type: "text/plain",
          byte_size: payload.bytesize
        )
        attachment.file.attach(blob)
        upload = create_upload(
          user: owner,
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob,
          attachment: attachment
        )

        post release_quarantine_admin_forum_attachment_path(upload), params: {
          reason: "Independent review initially concluded this was safe.",
          confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
        }, as: :json
        assert_response :success
        upload.reload
        assert_predicate upload, :manual_review_status_released?

        delete identity_session_path
        sign_in_as(owner)
        get forum_attachment_path(attachment)
        assert_response :success
        assert_equal "private, no-store", response.headers["Cache-Control"]

        delete identity_session_path
        sign_in_as(@admin)
        get admin_forum_attachments_path
        row = inertia.props.deep_symbolize_keys.fetch(:uploads).find { |item| item[:id] == upload.id }
        assert_equal(
          revoke_release_admin_forum_attachment_path(upload),
          row.dig(:actions, :revoke_release_url)
        )
        confirmation = row.dig(:actions, :revoke_confirmation)

        assert_difference(
          -> {
            AuditLog.where(
              action: "admin.forum_attachment_quarantine_release_revoked",
              resource_id: upload.id
            ).count
          },
          1
        ) do
          post revoke_release_admin_forum_attachment_path(upload), params: {
            reason: "New evidence invalidates the previous false-positive decision.",
            confirmation: confirmation
          }, as: :json
        end

        assert_response :success
        assert_equal true, JSON.parse(response.body).fetch("revoked")
        upload.reload
        assert_predicate upload, :manual_review_status_revoked?
        assert_predicate upload, :scan_status_infected?
        assert_equal "manual_release_revoked", upload.scan_result_code
        assert_equal 2, upload.manual_review_version
        assert upload.quarantined_at.present?

        delete identity_session_path
        sign_in_as(owner)
        get forum_attachment_path(attachment)
        assert_response :locked
      end

      test "attachment manager cannot release quarantine without independent permission" do
        grant_permission(@admin, "forum.attachments.security.manage")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("quarantined attachment"),
          filename: "blocked-release.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        post release_quarantine_admin_forum_attachment_path(upload), params: {
          reason: "This reason is intentionally long enough.",
          confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
        }

        assert_redirected_to root_path
        assert_predicate upload.reload, :scan_status_infected?
      end

      test "release reviewer cannot act without permission to inspect attachment evidence" do
        delete identity_session_path
        reviewer = create_user
        grant_permission(reviewer, "admin.access")
        grant_permission(reviewer, "forum.attachments.security.release")
        sign_in_as(reviewer)
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("quarantined attachment"),
          filename: "evidence-required.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        post release_quarantine_admin_forum_attachment_path(upload), params: {
          reason: "This review cannot proceed without evidence access.",
          confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
        }

        assert_redirected_to root_path
        assert_predicate upload.reload, :scan_status_infected?
      end

      test "manual review cannot release a file type rejected by the structural inspector" do
        grant_permission(@admin, "forum.attachments.security.release")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("not an allowed executable"),
          filename: "blocked.exe",
          content_type: "application/octet-stream"
        )
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        assert_no_difference(
          -> { AuditLog.where(action: "admin.forum_attachment_quarantine_released").count }
        ) do
          post release_quarantine_admin_forum_attachment_path(upload), params: {
            reason: "Independent review requested an unsafe release.",
            confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
          }
        end

        assert_redirected_to admin_forum_attachments_path(filter: "quarantined")
        assert_predicate upload.reload, :scan_status_infected?
        assert upload.quarantined_at.present?
      end

      test "reviewer cannot release an attachment they uploaded themselves" do
        grant_permission(@admin, "forum.attachments.security.release")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("self reviewed attachment"),
          filename: "self-review.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          user: @admin,
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        get admin_forum_attachments_path, params: { filter: "quarantined" }
        row = inertia.props.deep_symbolize_keys.fetch(:uploads).find { |item| item[:id] == upload.id }
        refute row.dig(:actions, :release_quarantine_url)

        post release_quarantine_admin_forum_attachment_path(upload), params: {
          reason: "A reviewer cannot approve their own upload.",
          confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
        }

        assert_redirected_to admin_forum_attachments_path(filter: "quarantined")
        assert_predicate upload.reload, :scan_status_infected?
      end

      test "scanner errors remain quarantined and cannot be relabeled as false positives" do
        grant_permission(@admin, "forum.attachments.security.release")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("unverified after scanner failure"),
          filename: "scanner-error.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          scan_status: "error",
          quarantined_at: Time.current,
          scan_result_code: "scanner_timeout",
          blob: blob
        )

        get admin_forum_attachments_path, params: { filter: "quarantined" }
        row = inertia.props.deep_symbolize_keys.fetch(:uploads).find { |item| item[:id] == upload.id }
        refute row.dig(:actions, :release_quarantine_url)

        post release_quarantine_admin_forum_attachment_path(upload), params: {
          reason: "A timeout is not evidence that the file is safe.",
          confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
        }

        assert_redirected_to admin_forum_attachments_path(filter: "quarantined")
        assert_predicate upload.reload, :scan_status_error?
        assert upload.quarantined_at.present?
      end

      test "release rolls back the state transition when immutable audit persistence fails" do
        grant_permission(@admin, "forum.attachments.security.release")
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("rollback attachment"),
          filename: "rollback.txt",
          content_type: "text/plain"
        )
        upload = create_upload(
          scan_status: "infected",
          quarantined_at: Time.current,
          scan_result_code: "malware_detected",
          blob: blob
        )

        result = Administration::AuditLogger.stub(
          :call,
          ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
        ) do
          Community::ReleaseQuarantinedUpload.call(
            upload: upload,
            actor: @admin,
            reason: "Independent review confirms a false positive.",
            confirmation: Community::ReleaseQuarantinedUpload.confirmation_for(upload)
          )
        end

        assert_predicate result, :failure?
        assert_equal "failed", result.code
        assert_predicate upload.reload, :scan_status_infected?
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

      test "admin access without attachment read permission cannot inspect uploads" do
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
        user: nil,
        status: "stored",
        scan_status: "pending",
        quarantined_at: nil,
        scan_result_code: nil,
        scan_error_message: nil,
        cleanup_error_code: nil,
        cleanup_error_message: nil,
        blob: nil,
        attachment: nil
      )
        Community::Upload.create!(
          user: user || create_user,
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
          post_attachment: attachment,
          expires_at: 1.day.from_now
        )
      end
    end
  end
end
