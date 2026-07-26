# frozen_string_literal: true

require "test_helper"

module Community
  class CleanupUploadOrphanSafetyTest < ActiveSupport::TestCase
    test "orphan cleanup rechecks the attachment link under lock" do
      user = create_user
      _topic, post = create_visible_forum_notification_resource(user: user)
      attachment = Community::PostAttachment.create!(
        user: user,
        filename: "race-safe.txt",
        content_type: "text/plain",
        byte_size: 4
      )
      attachment.file.attach(
        io: StringIO.new("data"),
        filename: "race-safe.txt",
        content_type: "text/plain"
      )
      mark_attachment_scan_clean!(attachment)
      upload = attachment.reload.upload_record

      attachment.update!(post: post)
      upload.update!(post: post, status: "linked", expires_at: nil)

      result = Community::CleanupUpload.call(
        upload: upload,
        orphan_only: true
      )

      assert result.success?, result.error
      assert_equal "not_orphan", result.value[:skipped]
      assert Community::PostAttachment.exists?(attachment.id)
      assert attachment.reload.file.attached?
      assert_predicate upload.reload, :status_linked?
      assert_equal post.id, upload.forum_post_id
    end
  end
end
