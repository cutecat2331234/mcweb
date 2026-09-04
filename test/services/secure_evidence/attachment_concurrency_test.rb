# frozen_string_literal: true

require "test_helper"
require "tempfile"
require "timeout"

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
        discard_authorizer: ->(actor:, subject:, attachment:) {
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

    test "slow object storage for one subject does not block another subject" do
      other_subject = create_user
      registry = SubjectRegistry.new
      registry.register(
        key: "test.parallel_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor.id == @user.id && subject.persisted? },
        download_authorizer: ->(actor:, subject:, attachment:) {
          actor.id == @user.id && attachment.subject_id == subject.id
        },
        retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
        max_files: 4,
        max_file_bytes: 1.megabyte,
        max_total_bytes: 4.megabytes,
        allowed_extensions: %w[txt]
      )
      registry.freeze!

      storage_started = Queue.new
      release_storage = Queue.new
      results = Queue.new
      connection_states = Queue.new
      block_mutex = Mutex.new
      block_next_upload = true
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |io|
        connection = ApplicationRecord.connection_pool.active_connection
        connection_states << [ connection.present?, connection&.transaction_open? == true ]
        should_block = block_mutex.synchronize do
          next false unless block_next_upload

          block_next_upload = false
          true
        end
        if should_block
          storage_started << true
          release_storage.pop
        end
        original_upload.bind_call(self, io)
      end

      first_file = nil
      first = Thread.new do
        first_file = uploaded_file("slow first subject")
        results << [ :first, CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.parallel_case",
          subject_public_id: @user.public_id,
          file: first_file,
          idempotency_key: "parallel-evidence-first-0001",
          catalog: registry
        ) ]
      rescue StandardError => error
        results << [ :first, error ]
      ensure
        first_file&.tempfile&.close!
      end

      Timeout.timeout(5) { storage_started.pop }
      second_file = nil
      second = Thread.new do
        second_file = uploaded_file("fast second subject")
        results << [ :second, CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.parallel_case",
          subject_public_id: other_subject.public_id,
          file: second_file,
          idempotency_key: "parallel-evidence-second-001",
          catalog: registry
        ) ]
      rescue StandardError => error
        results << [ :second, error ]
      ensure
        second_file&.tempfile&.close!
      end

      label, second_result = Timeout.timeout(5) { results.pop }
      assert_equal :second, label
      assert_instance_of ServiceResult, second_result
      assert_predicate second_result, :success?
      assert first.alive?

      release_storage << true
      label, first_result = Timeout.timeout(5) { results.pop }
      assert_equal :first, label
      assert_instance_of ServiceResult, first_result
      assert_predicate first_result, :success?
      assert_equal [ [ false, false ], [ false, false ] ],
        2.times.map { connection_states.pop }
      first.join
      second.join
    ensure
      release_storage << true if release_storage && first&.alive?
      first&.join
      second&.join
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
      User.where(id: other_subject&.id).delete_all
    end

    test "an in-flight idempotent retry shares one subject and site reservation" do
      registry = SubjectRegistry.new
      registry.register(
        key: "test.single_slot_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor.id == subject.id },
        download_authorizer: ->(actor:, subject:, attachment:) {
          actor.id == subject.id && attachment.subject_id == subject.id
        },
        retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
        max_files: 1,
        max_file_bytes: 1.megabyte,
        max_total_bytes: 1.megabyte,
        allowed_extensions: %w[txt]
      )
      registry.freeze!

      storage_started = Queue.new
      release_storage = Queue.new
      result_queue = Queue.new
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |io|
        storage_started << true
        release_storage.pop
        original_upload.bind_call(self, io)
      end

      first = Thread.new do
        file = uploaded_file("slow evidence")
        result_queue << CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.single_slot_case",
          subject_public_id: @user.public_id,
          file:,
          idempotency_key: "slow-evidence-idempotency-1",
          catalog: registry
        )
      rescue StandardError => error
        result_queue << error
      ensure
        file&.tempfile&.close!
      end

      Timeout.timeout(5) { storage_started.pop }
      leased_upload = Community::Upload.find_by!(
        user_id: @user.id,
        kind: "secure_evidence_attachment"
      )
      assert_operator leased_upload.expires_at, :>, Time.current
      assert_operator leased_upload.expires_at, :<, 2.hours.from_now
      replay_file = uploaded_file("slow evidence")
      replay = CreateAttachment.call(
        actor: @user,
        subject_key: "test.single_slot_case",
        subject_public_id: @user.public_id,
        file: replay_file,
        idempotency_key: "slow-evidence-idempotency-1",
        catalog: registry
      )
      other_file = uploaded_file("other evidence")
      other = CreateAttachment.call(
        actor: @user,
        subject_key: "test.single_slot_case",
        subject_public_id: @user.public_id,
        file: other_file,
        idempotency_key: "slow-evidence-idempotency-2",
        catalog: registry
      )

      assert_predicate replay, :success?
      assert_equal true, replay.value.fetch(:idempotent)
      assert_equal "uploading", replay.value.fetch(:attachment).state
      assert_predicate other, :failure?
      assert_equal "secure_evidence_file_limit_exceeded", other.code
      assert_equal 1, Community::Upload.where(
        user_id: @user.id,
        kind: "secure_evidence_attachment"
      ).count

      release_storage << true
      first_result = Timeout.timeout(5) { result_queue.pop }
      first.join
      assert_instance_of ServiceResult, first_result
      assert_predicate first_result, :success?
      assert_equal replay.value.fetch(:attachment).id,
        first_result.value.fetch(:attachment).id
    ensure
      release_storage << true if release_storage && first&.alive?
      first&.join
      replay_file&.tempfile&.close!
      other_file&.tempfile&.close!
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
    end

    test "discard preserves an in-flight upload lease until the writer returns" do
      storage_started = Queue.new
      release_storage = Queue.new
      results = Queue.new
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |io|
        storage_started << true
        release_storage.pop
        original_upload.bind_call(self, io)
      end

      worker = Thread.new do
        file = uploaded_file("discard during upload")
        results << CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.concurrent_case",
          subject_public_id: @user.public_id,
          file:,
          idempotency_key: "discard-upload-lease-0001",
          catalog: @registry
        )
      rescue StandardError => error
        results << error
      ensure
        file&.tempfile&.close!
      end

      Timeout.timeout(5) { storage_started.pop }
      attachment = Attachment.find_by!(
        uploader_id: @user.id,
        idempotency_key: "discard-upload-lease-0001"
      )
      upload = attachment.upload_record
      writer_lease = upload.expires_at

      discarded = DiscardAttachment.call(
        attachment:,
        actor: @user,
        catalog: @registry,
        now: Time.current
      )

      assert_predicate discarded, :success?, discarded.error
      assert_equal "purge_pending", attachment.reload.state
      assert_equal "cleanup_pending", upload.reload.status
      assert_equal writer_lease.to_i, upload.expires_at.to_i

      release_storage << true
      writer_result = Timeout.timeout(5) { results.pop }
      worker.join
      assert_instance_of ServiceResult, writer_result
      assert_predicate writer_result, :failure?
      assert_operator upload.reload.expires_at, :<=, Time.current
    ensure
      release_storage << true if release_storage && worker&.alive?
      worker&.join
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
    end

    test "an expired cleanup worker cannot finish or fail a reclaimed generation" do
      file = uploaded_file("cleanup generation fence")
      created = CreateAttachment.call(
        actor: @user,
        subject_key: "test.concurrent_case",
        subject_public_id: @user.public_id,
        file:,
        idempotency_key: "cleanup-generation-fence-0001",
        catalog: @registry
      )
      attachment = created.value.fetch(:attachment)
      file.tempfile.close!
      discarded = DiscardAttachment.call(
        attachment:,
        actor: @user,
        catalog: @registry
      )
      assert_predicate discarded, :success?
      upload = attachment.upload_record

      first_worker = Community::CleanupUpload.new(upload:, now: Time.current)
      first_claim = first_worker.send(:claim_cleanup)
      assert_predicate first_claim, :success?
      first_snapshot = first_claim.value
      upload.update_columns(cleanup_started_at: 31.minutes.ago)

      second_worker = Community::CleanupUpload.new(upload:, now: Time.current)
      second_claim = second_worker.send(:claim_cleanup)
      assert_predicate second_claim, :success?
      second_snapshot = second_claim.value
      assert_operator second_snapshot.fetch(:cleanup_attempt), :>,
        first_snapshot.fetch(:cleanup_attempt)

      stale_finish = first_worker.send(:finish_cleanup, first_snapshot)
      first_worker.send(
        :record_failure,
        IOError.new("stale cleanup failure"),
        snapshot: first_snapshot
      )

      assert_predicate stale_finish, :success?
      assert_equal "cleanup_superseded", stale_finish.value.fetch(:skipped)
      assert_equal "cleanup_pending", upload.reload.status
      assert_equal second_snapshot.fetch(:cleanup_attempt), upload.cleanup_attempts
      assert_equal 0, attachment.events.where(event_type: "cleanup_failed").count

      second_worker.send(:purge_blob, second_snapshot.fetch(:blob_id))
      completed = second_worker.send(:finish_cleanup, second_snapshot)

      assert_predicate completed, :success?
      assert_equal "cleaned", upload.reload.status
      assert_equal "purged", attachment.reload.state
    end

    test "a timed out worker cannot overwrite or fail a reused idempotent attempt" do
      registry = SubjectRegistry.new
      registry.register(
        key: "test.reused_attempt_case",
        model_name: "User",
        resolver: ->(public_id:) { User.find_by(public_id:) },
        upload_authorizer: ->(actor:, subject:) { actor.id == subject.id },
        download_authorizer: ->(actor:, subject:, attachment:) {
          actor.id == subject.id && attachment.subject_id == subject.id
        },
        retention: ->(subject:, attached_at:) { attached_at + 30.days if subject.persisted? },
        max_files: 1,
        max_file_bytes: 1.megabyte,
        max_total_bytes: 1.megabyte,
        allowed_extensions: %w[txt]
      )
      registry.freeze!

      first_started = Queue.new
      release_first = Queue.new
      second_started = Queue.new
      release_second = Queue.new
      results = Queue.new
      call_mutex = Mutex.new
      call_count = 0
      original_upload = ActiveStorage::Blob.instance_method(:upload_without_unfurling)
      ActiveStorage::Blob.define_method(:upload_without_unfurling) do |io|
        call_number = call_mutex.synchronize do
          call_count += 1
        end
        if call_number == 1
          first_started << true
          release_first.pop
        elsif call_number == 2
          second_started << true
          release_second.pop
        end
        original_upload.bind_call(self, io)
      end

      first_file = nil
      first = Thread.new do
        first_file = uploaded_file("reused attempt evidence")
        results << [ :first, CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.reused_attempt_case",
          subject_public_id: @user.public_id,
          file: first_file,
          idempotency_key: "reused-attempt-evidence-0001",
          catalog: registry
        ) ]
      rescue StandardError => error
        results << [ :first, error ]
      ensure
        first_file&.tempfile&.close!
      end

      Timeout.timeout(5) { first_started.pop }
      attachment = Attachment.find_by!(
        uploader_id: @user.id,
        idempotency_key: "reused-attempt-evidence-0001"
      )
      upload = attachment.upload_record
      first_blob_id = upload.active_storage_blob_id
      first_blob_key = upload.blob.key
      upload.update!(expires_at: 1.minute.ago)

      cleanup = Community::CleanupUpload.call(upload:, now: Time.current)
      assert_predicate cleanup, :success?
      assert_equal "upload_failed", attachment.reload.state
      assert_equal "cleaned", upload.reload.status
      refute ActiveStorage::Blob.exists?(first_blob_id)

      second_file = nil
      second = Thread.new do
        second_file = uploaded_file("reused attempt evidence")
        results << [ :second, CreateAttachment.call(
          actor: User.find(@user.id),
          subject_key: "test.reused_attempt_case",
          subject_public_id: @user.public_id,
          file: second_file,
          idempotency_key: "reused-attempt-evidence-0001",
          catalog: registry
        ) ]
      rescue StandardError => error
        results << [ :second, error ]
      ensure
        second_file&.tempfile&.close!
      end

      Timeout.timeout(5) { second_started.pop }
      current_blob_id = upload.reload.active_storage_blob_id
      assert_not_equal first_blob_id, current_blob_id

      release_first << true
      label, stale_result = Timeout.timeout(5) { results.pop }
      assert_equal :first, label
      assert_instance_of ServiceResult, stale_result
      assert_predicate stale_result, :failure?
      assert_equal "secure_evidence_upload_failed", stale_result.code
      assert_equal "uploading", attachment.reload.state
      assert_equal "reserved", upload.reload.status
      assert_equal current_blob_id, upload.active_storage_blob_id
      refute ActiveStorage::Blob.service.exist?(first_blob_key)

      release_second << true
      label, retry_result = Timeout.timeout(5) { results.pop }
      assert_equal :second, label
      assert_instance_of ServiceResult, retry_result
      assert_predicate retry_result, :success?
      assert_equal attachment.id, retry_result.value.fetch(:attachment).id
      assert_equal "pending", attachment.reload.state
      assert_equal "stored", upload.reload.status
      assert_equal 1, Attachment.where(
        uploader_id: @user.id,
        subject_key: "test.reused_attempt_case"
      ).count
      assert_equal 1, Community::Upload.where(
        user_id: @user.id,
        kind: "secure_evidence_attachment"
      ).count
      first.join
      second.join
    ensure
      release_first << true if release_first && first&.alive?
      release_second << true if release_second && second&.alive?
      first&.join
      second&.join
      ActiveStorage::Blob.define_method(:upload_without_unfurling, original_upload) if original_upload
    end

    test "concurrent discard requests create one transition and one immutable event" do
      file = uploaded_file("concurrent discard")
      created = CreateAttachment.call(
        actor: @user,
        subject_key: "test.concurrent_case",
        subject_public_id: @user.public_id,
        file:,
        idempotency_key: "concurrent-discard-0001",
        catalog: @registry
      )
      attachment = created.value.fetch(:attachment)
      file.tempfile.close!

      ready = Queue.new
      gate = Queue.new
      results = Queue.new
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            gate.pop
            results << DiscardAttachment.call(
              attachment: Attachment.find(attachment.id),
              actor: User.find(@user.id),
              catalog: @registry
            )
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
      assert_equal "purge_pending", attachment.reload.state
      assert_equal 1, attachment.events.where(event_type: "discarded").count
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
