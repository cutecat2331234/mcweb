# frozen_string_literal: true

require "test_helper"
require "tempfile"

module SecureEvidence
  class AttachmentConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @user = create_user
      @registry = SubjectRegistry.new
      @registry.register(
        key: "test.concurrent_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor.id == subject.id },
        download_authorizer: ->(actor:, subject:, attachment:) {
          actor.id == subject.id && attachment.subject_id == subject.id
        },
        retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
        max_files: 4,
        max_file_bytes: 1.megabyte,
        max_total_bytes: 4.megabytes,
        allowed_extensions: %w[txt]
      )
      @registry.freeze!
    end

    teardown do
      cleanup_records
      clear_enqueued_jobs
    end

    test "concurrent identical requests create one attachment and replay the same public id" do
      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            file = uploaded_file("concurrent evidence")
            ready << true
            gate.pop
            results << CreateAttachment.call(
              actor: User.find(@user.id),
              subject_key: "test.concurrent_case",
              subject_public_id: @user.public_id,
              file:,
              idempotency_key: "concurrent-evidence-0001",
              catalog: @registry
            )
          ensure
            file&.tempfile&.close!
          end
        rescue StandardError => error
          results << error
        end
      end

      2.times { ready.pop }
      2.times { gate << true }
      responses = 2.times.map { results.pop }
      threads.each(&:join)

      responses.each { |response| assert_instance_of ServiceResult, response }
      assert responses.all?(&:success?)
      assert_equal 1, responses.count { |item| item.value.fetch(:idempotent) }
      assert_equal 1, responses.count { |item| !item.value.fetch(:idempotent) }
      assert_equal 1, Attachment.where(uploader_id: @user.id).count
      assert_equal 1, Community::Upload.where(
        user_id: @user.id,
        kind: "secure_evidence_attachment"
      ).count
      assert_equal 1, responses.map { |item| item.value.fetch(:attachment).public_id }.uniq.length
    end

    private

    def uploaded_file(content)
      tempfile = Tempfile.new([ "evidence", ".txt" ])
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind
      ActionDispatch::Http::UploadedFile.new(
        tempfile:,
        filename: "concurrent.txt",
        type: "text/plain"
      )
    end

    def cleanup_records
      attachments = Attachment.where(uploader_id: @user&.id)
      attachment_ids = attachments.pluck(:id)
      uploads = Community::Upload.where(secure_evidence_attachment_id: attachment_ids)
      upload_ids = uploads.pluck(:id)
      blob_ids = uploads.pluck(:active_storage_blob_id).compact

      ActiveStorage::Blob.where(id: blob_ids).find_each(&:purge)
      uploads.update_all(secure_evidence_attachment_id: nil)
      Community::Upload.where(id: upload_ids).delete_all
      AuditLog.where(
        resource_type: "SecureEvidence::Attachment",
        resource_id: attachment_ids
      ).delete_all

      with_mutable_evidence_records do
        AttachmentEvent.where(secure_evidence_attachment_id: attachment_ids).delete_all
        attachments.delete_all
      end
    end

    def with_mutable_evidence_records
      connection = ApplicationRecord.connection
      triggers = {
        secure_evidence_attachment_events: :secure_evidence_attachment_events_immutable,
        secure_evidence_attachments: :secure_evidence_attachments_reject_delete
      }
      triggers.each do |table, trigger|
        connection.execute(
          "ALTER TABLE #{connection.quote_table_name(table)} " \
          "DISABLE TRIGGER #{connection.quote_column_name(trigger)}"
        )
      end
      yield
    ensure
      triggers&.to_a&.reverse_each do |table, trigger|
        connection.execute(
          "ALTER TABLE #{connection.quote_table_name(table)} " \
          "ENABLE TRIGGER #{connection.quote_column_name(trigger)}"
        )
      end
    end
  end
end
