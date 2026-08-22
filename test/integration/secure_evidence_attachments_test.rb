# frozen_string_literal: true

require "test_helper"
require "tempfile"

class SecureEvidenceAttachmentsTest < ActionDispatch::IntegrationTest
  setup do
    @user = create_user
    @allowed = true
    @linked = false
    @entry = SecureEvidence::SubjectRegistry.new.register(
      key: "test.evidence_case",
      model_name: "User",
      resolver: ->(public_id:) { User.find_by(public_id:) },
      upload_authorizer: ->(actor:, subject:) { @allowed && actor.id == subject.id },
      download_authorizer: ->(actor:, subject:, attachment:) {
        @allowed && actor.id == subject.id && attachment.subject_id == subject.id
      },
      discard_authorizer: ->(actor:, subject:, attachment:) {
        @allowed &&
          !@linked &&
          actor.id == subject.id &&
          attachment.subject_id == subject.id
      },
      retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
      max_files: 4,
      max_file_bytes: 1.megabyte,
      max_total_bytes: 4.megabytes,
      allowed_extensions: %w[txt]
    )
    sign_in_as(@user)
  end

  test "generic API creates status-checks and streams only through an authorized app path" do
    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      post secure_evidence_attachments_path, params: {
        subject_key: @entry.key,
        subject_public_id: @user.public_id,
        idempotency_key: "integration-evidence-0001",
        file: upload("browser evidence")
      }
    end

    assert_response :created
    payload = response.parsed_body
    assert_match(%r{\A/app/evidence/attachments/}, payload.fetch("download_url"))
    assert_match(%r{\A/app/evidence/attachments/}, payload.fetch("scan_status_url"))
    assert_match(%r{\A/app/evidence/attachments/}, payload.fetch("discard_url"))
    assert Time.iso8601(payload.fetch("updated_at"))
    refute_includes response.body, "/rails/active_storage/"
    refute_includes response.body, "blob"

    attachment = SecureEvidence::Attachment.find_by!(public_id: payload.fetch("public_id"))
    newer_upload_time = 1.minute.from_now.change(usec: 123_456)
    attachment.upload_record.update!(updated_at: newer_upload_time)
    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      get scan_status_secure_evidence_attachment_path(attachment)
    end
    assert_response :ok
    assert_equal "pending", response.parsed_body.fetch("state")
    assert_equal newer_upload_time.iso8601(6), response.parsed_body.fetch("updated_at")

    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      get secure_evidence_attachment_path(attachment)
    end
    assert_response :locked
    refute attachment.events.where(event_type: "downloaded").exists?

    Community::ScanPostAttachment.call(
      upload: attachment.upload_record,
      scanner: clean_scanner,
      now: Time.current
    )
    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      get secure_evidence_attachment_path(attachment)
    end

    assert_response :ok
    assert_equal "browser evidence", response.body
    disposition = response.headers.fetch("Content-Disposition")
    assert_includes disposition, "attachment"
    assert_includes disposition, "browser-evidence.txt"
    assert_equal "text/plain", response.media_type
    assert_equal "nosniff", response.headers.fetch("X-Content-Type-Options")
    assert_equal "sandbox", response.headers.fetch("Content-Security-Policy")
    assert_equal "same-origin", response.headers.fetch("Cross-Origin-Resource-Policy")
    assert_match(/private/, response.headers.fetch("Cache-Control"))
    assert attachment.events.where(event_type: "downloaded").exists?
    assert AuditLog.exists?(
      action: "secure_evidence.downloaded",
      resource_public_id: attachment.public_id
    )
  ensure
    @temporary_file&.close!
  end

  test "generic API discards only uploader-owned unlinked evidence with private idempotent responses" do
    result = SecureEvidence::CreateAttachment.call(
      actor: @user,
      subject_key: @entry.key,
      subject_public_id: @user.public_id,
      file: upload("discard through API"),
      idempotency_key: "integration-evidence-discard-1",
      catalog: Struct.new(:entry) {
        def entry_for_key(_key) = entry
      }.new(@entry)
    )
    attachment = result.value.fetch(:attachment)

    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      delete secure_evidence_attachment_path(attachment)
    end
    assert_response :ok
    assert_match(/private/, response.headers.fetch("Cache-Control"))
    assert_match(/no-store/, response.headers.fetch("Cache-Control"))
    assert_equal "no-cache", response.headers.fetch("Pragma")
    assert_equal "purge_pending", response.parsed_body.fetch("state")
    assert_equal false, response.parsed_body.fetch("idempotent")
    assert Time.iso8601(response.parsed_body.fetch("updated_at"))

    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      delete secure_evidence_attachment_path(attachment)
    end
    assert_response :ok
    assert_equal true, response.parsed_body.fetch("idempotent")
    assert_equal 1, attachment.events.where(event_type: "discarded").count

    denied = SecureEvidence::CreateAttachment.call(
      actor: @user,
      subject_key: @entry.key,
      subject_public_id: @user.public_id,
      file: upload("linked evidence"),
      idempotency_key: "integration-evidence-discard-2",
      catalog: Struct.new(:entry) {
        def entry_for_key(_key) = entry
      }.new(@entry)
    ).value.fetch(:attachment)
    @linked = true
    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      delete secure_evidence_attachment_path(denied)
    end
    assert_response :not_found
    assert_match(/no-store/, response.headers.fetch("Cache-Control"))

    delete secure_evidence_attachment_path("missing-evidence")
    assert_response :not_found
    assert_match(/no-store/, response.headers.fetch("Cache-Control"))
  ensure
    @temporary_file&.close!
  end

  test "missing and newly unauthorized subjects are indistinguishable" do
    result = SecureEvidence::CreateAttachment.call(
      actor: @user,
      subject_key: @entry.key,
      subject_public_id: @user.public_id,
      file: upload("private evidence"),
      idempotency_key: "integration-evidence-0002",
      catalog: Struct.new(:entry) {
        def entry_for_key(_key) = entry
      }.new(@entry)
    )
    attachment = result.value.fetch(:attachment)
    @allowed = false

    SecureEvidence::SubjectCatalog.stub(:entry_for_key, @entry) do
      get secure_evidence_attachment_path(attachment)
    end
    assert_response :not_found

    get secure_evidence_attachment_path("missing-evidence")
    assert_response :not_found
  ensure
    @temporary_file&.close!
  end

  private

  def upload(content)
    @temporary_file&.close!
    @temporary_file = Tempfile.new([ "evidence", ".txt" ])
    @temporary_file.binmode
    @temporary_file.write(content)
    @temporary_file.rewind
    Rack::Test::UploadedFile.new(
      @temporary_file.path,
      "text/plain",
      original_filename: "browser-evidence.txt"
    )
  end

  def clean_scanner
    result = Community::AttachmentMalwareScanner::Result.new(
      status: :clean,
      scanner: "integration_scanner",
      code: "clean",
      error_message: nil
    )
    ->(blob:) { result if blob }
  end
end
