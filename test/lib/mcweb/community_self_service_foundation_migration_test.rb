# frozen_string_literal: true

require "test_helper"
require Rails.root.join(
  "db/migrate/20260821090000_add_community_self_service_foundation"
)

class CommunitySelfServiceFoundationMigrationTest < ActiveSupport::TestCase
  test "legacy messages receive an encrypted initial revision" do
    sender = create_user
    recipient = create_user
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    now = Time.current
    inserted = Community::Message.insert_all!([ {
      forum_conversation_id: conversation.id,
      user_id: sender.id,
      body: "Legacy private message #{SecureRandom.hex(8)}",
      revision: 1,
      created_at: now,
      updated_at: now
    } ], returning: %w[id])
    message_id = inserted.rows.first.first
    message = Community::Message.find(message_id)
    assert_empty Community::MessageRevision.where(forum_message_id: message_id)

    AddCommunitySelfServiceFoundation.new.send(:backfill_message_revisions)

    revision = Community::MessageRevision.find_by!(
      forum_message_id: message_id,
      revision: 1
    )
    assert_equal message.body, revision.body
    assert_equal sender.id, revision.editor_id
    assert_equal Digest::SHA256.hexdigest(message.body), revision.content_digest
    assert_predicate revision, :digest_valid?
    refute_includes revision.encrypted_body, message.body
  end

  test "rollback marks private-message uploads for cleanup before dropping ownership" do
    sender = create_user
    recipient = create_user
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    message = conversation.messages.create!(user: sender, body: "Message with attachment")
    attachment = Community::PostAttachment.create!(
      user: sender,
      message: message,
      filename: "rollback-private.txt",
      content_type: "text/plain",
      byte_size: 4
    )
    attachment.file.attach(
      io: StringIO.new("data"),
      filename: attachment.filename,
      content_type: attachment.content_type
    )
    mark_attachment_scan_clean!(attachment)
    upload = attachment.reload.upload_record
    upload.update!(status: "linked", expires_at: nil)

    AddCommunitySelfServiceFoundation.new.send(
      :schedule_message_attachment_cleanup_for_rollback
    )

    assert_predicate upload.reload, :status_cleanup_pending?
    assert_not_nil upload.expires_at
    assert_nil upload.cleanup_started_at
    assert_includes Community::Upload.cleanup_due(1.minute.from_now), upload
  end

  test "rollback preserves compatibility permissions and all pre-existing grants" do
    migration_class = Class.new(AddCommunitySelfServiceFoundation) do
      attr_reader :statements

      def initialize
        super
        @statements = []
      end

      def execute(sql)
        @statements << sql.to_s
      end

      def remove_check_constraint(*args, **kwargs); end
      def remove_column(*args, **kwargs); end
      def remove_reference(*args, **kwargs); end
      def drop_table(*args, **kwargs); end
      def remove_index(*args, **kwargs); end
    end
    migration = migration_class.new

    migration.down

    sql = migration.statements.join("\n")
    assert_match(/UPDATE forum_uploads AS uploads/i, sql)
    refute_match(/DELETE\s+FROM\s+permissions/i, sql)
    refute_match(/DELETE\s+FROM\s+role_permissions/i, sql)
  end
end
