# frozen_string_literal: true

require "test_helper"

module Community
  class ManualAttachmentReleaseStateTest < ActiveSupport::TestCase
    setup do
      @reviewer = create_user
      grant_permission(@reviewer, ::Community::ReleaseQuarantinedUpload::PERMISSION)
      @owner = create_user
      @payload = "manual review state payload"
      @blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(@payload),
        filename: "review-state.txt",
        content_type: "text/plain"
      )
      attachment = PostAttachment.create!(
        user: @owner,
        filename: "review-state.txt",
        content_type: "text/plain",
        byte_size: @payload.bytesize
      )
      attachment.file.attach(@blob)
      @upload = Upload.create!(
        user: @owner,
        public_id: Upload.generate_public_id,
        kind: "post_attachment",
        status: "stored",
        byte_size: @payload.bytesize,
        scan_status: "infected",
        scan_result_code: "malware_detected",
        quarantined_at: Time.current,
        expires_at: 1.day.from_now,
        blob: @blob,
        post_attachment: attachment
      )
    end

    test "revocation rolls back when immutable audit persistence fails" do
      release!

      result = Administration::AuditLogger.stub(
        :call,
        ->(**) { raise ActiveRecord::StatementInvalid, "audit unavailable" }
      ) do
        ::Community::RevokeQuarantinedUploadRelease.call(
          upload: @upload,
          actor: @reviewer,
          reason: "New evidence requires the release to be revoked.",
          confirmation: ::Community::RevokeQuarantinedUploadRelease.confirmation_for(@upload)
        )
      end

      assert result.failure?
      assert_equal "failed", result.code
      @upload.reload
      assert_predicate @upload, :manual_review_status_released?
      assert_predicate @upload, :scan_status_clean?
      assert_equal 1, @upload.manual_review_version
    end

    test "stale version-bound revocation confirmation cannot change the state" do
      release!
      stale_confirmation = ::Community::RevokeQuarantinedUploadRelease.confirmation_for(@upload)
      @upload.increment!(:manual_review_version)

      result = ::Community::RevokeQuarantinedUploadRelease.call(
        upload: @upload,
        actor: @reviewer,
        reason: "This stale request must not revoke a newer decision.",
        confirmation: stale_confirmation
      )

      assert result.failure?
      assert_equal "confirmation_mismatch", result.code
      assert_predicate @upload.reload, :manual_review_status_released?
      assert_predicate @upload, :scan_status_clean?
    end

    test "rescan after revocation starts a new review generation" do
      release!
      revoke!
      revoked_version = @upload.reload.manual_review_version

      assert_enqueued_with(
        job: ::Community::ScanPostAttachmentJob,
        args: [ { upload_id: @upload.id } ]
      ) do
        result = ::Community::RetryUploadScan.call(upload: @upload)
        assert result.success?
      end

      @upload.reload
      assert_predicate @upload, :manual_review_status_none?
      assert_predicate @upload, :scan_status_pending?
      assert_equal revoked_version + 1, @upload.manual_review_version
      assert_nil @upload.manual_review_file_sha256
      assert_nil @upload.manual_review_revoked_at
    end

    private

    def release!
      result = ::Community::ReleaseQuarantinedUpload.call(
        upload: @upload,
        actor: @reviewer,
        reason: "Independent evidence confirms this detection is a false positive.",
        confirmation: ::Community::ReleaseQuarantinedUpload.confirmation_for(@upload)
      )
      assert result.success?
      @upload.reload
    end

    def revoke!
      result = ::Community::RevokeQuarantinedUploadRelease.call(
        upload: @upload,
        actor: @reviewer,
        reason: "New evidence invalidates the prior false-positive decision.",
        confirmation: ::Community::RevokeQuarantinedUploadRelease.confirmation_for(@upload)
      )
      assert result.success?
      @upload.reload
    end
  end
end
