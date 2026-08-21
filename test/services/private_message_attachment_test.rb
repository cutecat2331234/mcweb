# frozen_string_literal: true

require "test_helper"

class PrivateMessageAttachmentTest < ActiveSupport::TestCase
  setup do
    DataGovernance::RetentionPolicy.ensure_defaults!
    @sender = create_user(forum_trust_level_override: 1)
    @recipient = create_user(forum_trust_level_override: 1)
    @outsider = create_user(forum_trust_level_override: 1)
    @conversation = Community::Conversation.create!
    @conversation.participants.create!(user: @sender)
    @conversation.participants.create!(user: @recipient)
  end

  test "a clean owned upload is atomically linked to a private message" do
    attachment = create_attachment(user: @sender, clean: true)

    result = Community::SendMessage.call(
      user: @sender,
      conversation: @conversation,
      body: "See the attached evidence.",
      attachment_ids: [ attachment.id ]
    )

    assert_predicate result, :success?, result.error
    message = result.value
    assert_equal message.id, attachment.reload.forum_message_id
    assert_nil attachment.forum_post_id
    assert_equal "linked", attachment.upload_record.reload.status
    assert_nil attachment.upload_record.expires_at
    assert Community::PostAttachmentAccess.downloadable?(attachment, user: @recipient)
    refute Community::PostAttachmentAccess.downloadable?(attachment, user: @outsider)
  end

  test "an unauthorized upload rolls back the message and all recipient side effects" do
    attachment = create_attachment(user: @outsider, clean: true)

    assert_no_enqueued_jobs do
      assert_no_difference -> { @conversation.messages.count } do
        assert_no_difference -> { @recipient.notifications.count } do
          result = Community::SendMessage.call(
            user: @sender,
            conversation: @conversation,
            body: "This must roll back.",
            attachment_ids: [ attachment.id ]
          )
          assert_predicate result, :failure?
          assert_equal "attachment_invalid_or_unauthorized", result.code
        end
      end
    end
    assert_nil attachment.reload.forum_message_id
    assert_equal "stored", attachment.upload_record.reload.status
  end

  test "an upload that has not passed scanning cannot be linked or notified" do
    attachment = create_attachment(user: @sender, clean: false)

    draft = Community::SaveMessageDraft.call(
      user: @sender,
      conversation: @conversation,
      body: "Pending draft",
      attachment_ids: [ attachment.id ]
    )
    assert_predicate draft, :failure?
    assert_equal "attachment_invalid_or_unauthorized", draft.code

    assert_no_difference -> { @conversation.messages.count } do
      assert_no_difference -> { @recipient.notifications.count } do
        result = Community::SendMessage.call(
          user: @sender,
          conversation: @conversation,
          body: "Pending files cannot be sent.",
          attachment_ids: [ attachment.id ]
        )
        assert_predicate result, :failure?
        assert_equal "attachment_invalid_or_unauthorized", result.code
      end
    end
    assert_nil attachment.reload.forum_message_id
    assert_equal "pending", attachment.upload_record.reload.scan_status
  end

  test "governed message purge schedules its linked upload and releases quota after cleanup" do
    attachment = create_attachment(user: @sender, clean: true)
    sent = Community::SendMessage.call(
      user: @sender,
      conversation: @conversation,
      body: "Retain this attachment until governed purge.",
      attachment_ids: [ attachment.id ]
    )
    assert_predicate sent, :success?, sent.error
    message = sent.value
    upload = attachment.reload.upload_record
    DataGovernance::RetentionPolicy.find_by!(resource_type: "Community::Message")
      .update!(retention_days: 0)

    deleted = Community::DeleteMessage.call(
      user: @sender,
      message: message,
      request_id: "message-delete-#{SecureRandom.uuid}"
    )

    assert_predicate deleted, :success?, deleted.error
    lifecycle = deleted.value.fetch(:lifecycle)
    assert_predicate lifecycle, :status_soft_deleted?
    assert_predicate upload.reload, :status_linked?
    assert_nil upload.expires_at
    refute Community::PostAttachmentAccess.downloadable?(attachment.reload, user: @recipient)

    purged = DataGovernance::PermanentlyPurgeContent.call(
      record: lifecycle,
      actor: @sender,
      reason: "Retention elapsed.",
      at: 1.minute.from_now
    )

    assert_predicate purged, :success?, purged.error
    refute Community::Message.with_discarded.exists?(message.id)
    refute Community::PostAttachment.with_discarded.exists?(attachment.id)
    assert_predicate upload.reload, :status_cleanup_pending?
    assert_not_nil upload.expires_at
    assert_includes Community::Upload.cleanup_due(1.minute.from_now), upload

    cleaned = Community::CleanupUpload.call(upload: upload, now: 1.minute.from_now)
    assert_predicate cleaned, :success?, cleaned.error
    assert_predicate upload.reload, :status_cleaned?
    assert_nil upload.active_storage_blob_id
    refute Community::Upload.counted_toward_quota.exists?(upload.id)
  end

  private

  def create_attachment(user:, clean:)
    attachment = Community::PostAttachment.create!(
      user: user,
      filename: "private-#{SecureRandom.hex(4)}.txt",
      content_type: "text/plain",
      byte_size: 4
    )
    attachment.file.attach(
      io: StringIO.new("data"),
      filename: attachment.filename,
      content_type: "text/plain"
    )
    mark_attachment_scan_clean!(attachment)
    unless clean
      attachment.upload_record.update!(
        scan_status: "pending",
        scanned_at: nil,
        scanner: nil,
        scan_result_code: nil
      )
    end
    attachment.reload
  end
end
