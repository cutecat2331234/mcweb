# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260821090000_add_community_self_service_foundation")
require Rails.root.join("db/migrate/20260821090100_backfill_community_message_revisions")
require Rails.root.join("db/migrate/20260821090200_contract_community_self_service_foundation")
require Rails.root.join("lib/mcweb/migrations/community_message_revision_contract")

class CommunitySelfServiceFoundationMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  MIGRATION_VERSIONS = [ 20260821090000, 20260821090100, 20260821090200 ].freeze

  setup do
    migrate_up!
    reset_feature_models!
  end

  teardown do
    migrate_up!
    reset_feature_models!
  end

  test "feature-fresh migration encrypts legacy rows and post-deploy gate closes concurrent writes" do
    migrate_down!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    legacy_body = "Legacy private message #{SecureRandom.hex(8)}"
    legacy_id = insert_legacy_message(conversation: conversation, sender: sender, body: legacy_body)

    migrate_up!
    reset_feature_models!

    legacy_revision = Community::MessageRevision.find_by!(
      forum_message_id: legacy_id,
      revision: 1
    )
    assert_equal legacy_body, legacy_revision.body
    assert_equal sender.id, legacy_revision.editor_id
    assert_predicate legacy_revision, :digest_valid?
    refute_includes legacy_revision.encrypted_body, legacy_body
    assert_all_contract_constraints_validated
    assert_all_concurrent_indexes_valid
    assert_not_null_contract

    late_body = "Old process write after migration #{SecureRandom.hex(8)}"
    late_id = insert_legacy_message(conversation: conversation, sender: sender, body: late_body)
    assert_empty Community::MessageRevision.where(forum_message_id: late_id)
    assert_equal 1, queue_count(late_id)

    moving_tail_body = "Old process moving tail #{SecureRandom.hex(8)}"
    install_moving_tail_trigger(
      source_message_id: late_id,
      conversation: conversation,
      sender: sender,
      body: moving_tail_body
    )
    begin
      bounded = Mcweb::Migrations::CommunityMessageRevisionBackfill.new(batch_size: 1).call
    ensure
      drop_moving_tail_trigger
    end

    moving_tail = Community::Message.with_discarded.find_by!(body: moving_tail_body)
    assert_equal 1, bounded.fetch(:missing)
    assert_equal 1, bounded.fetch(:queued)
    assert Community::MessageRevision.exists?(forum_message_id: late_id, revision: 1)
    assert_empty Community::MessageRevision.where(forum_message_id: moving_tail.id)
    assert_equal 1, queue_count(moving_tail.id)

    finalized = Mcweb::Migrations::CommunityMessageRevisionContract.new(batch_size: 2).call

    assert_equal true, finalized.fetch(:finalized)
    assert_equal 0, finalized.fetch(:missing)
    assert_equal 0, finalized.fetch(:queued)
    late_revision = Community::MessageRevision.find_by!(forum_message_id: late_id, revision: 1)
    assert_equal late_body, late_revision.body
    assert_predicate late_revision, :digest_valid?
    assert_equal 0, queue_count(late_id)

    rejected_body = "Old process write after gate #{SecureRandom.hex(8)}"
    assert_raises ActiveRecord::StatementInvalid do
      ActiveRecord::Base.transaction(requires_new: true) do
        insert_legacy_message(conversation: conversation, sender: sender, body: rejected_body)
      end
    end
    refute Community::Message.with_discarded.exists?(body: rejected_body)

    sent = Community::SendMessage.call(
      user: sender,
      conversation: conversation,
      body: "New dual-written message"
    )
    assert_predicate sent, :success?, sent.error
    assert_equal [ 1 ], sent.value.revisions.pluck(:revision)
    assert_equal 0, queue_count(sent.value.id)
  end

  test "actual down and up schedules attachments while retaining permissions and grants" do
    Mcweb::Migrations::CommunityMessageRevisionContract.new.call
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    message = conversation.messages.create!(user: sender, body: "Rollback attachment owner")
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

    permission = Permission.find_by!(key: AddCommunitySelfServiceFoundation::REVIEW_PERMISSION)
    role = Role.find_or_create_by!(key: "migration_permission_owner") do |record|
      record.name = "Migration permission owner"
    end
    role.grant_permission!(permission)
    grant_id = RolePermission.find_by!(role: role, permission: permission).id

    migrate_down!

    upload_state = connection.select_one(<<~SQL.squish)
      SELECT status, expires_at, cleanup_started_at
      FROM forum_uploads
      WHERE id = #{upload.id}
    SQL
    assert_equal "cleanup_pending", upload_state.fetch("status")
    assert_not_nil upload_state.fetch("expires_at")
    assert_nil upload_state.fetch("cleanup_started_at")
    refute connection.column_exists?(:forum_post_attachments, :forum_message_id)
    assert Permission.exists?(permission.id)
    assert RolePermission.exists?(grant_id)

    migrate_up!
    reset_feature_models!
    result = Mcweb::Migrations::CommunityMessageRevisionContract.new.call

    assert_equal true, result.fetch(:finalized)
    assert connection.column_exists?(:forum_post_attachments, :forum_message_id)
    assert Permission.exists?(permission.id)
    assert RolePermission.exists?(grant_id)
  end

  private

  def migration_context
    pool = ActiveRecord::Base.connection_pool
    ActiveRecord::MigrationContext.new(
      Rails.application.config.paths["db/migrate"].to_a,
      ActiveRecord::SchemaMigration.new(pool),
      ActiveRecord::InternalMetadata.new(pool)
    )
  end

  def migrate_down!
    context = migration_context
    MIGRATION_VERSIONS.reverse_each do |version|
      context.run(:down, version) if context.get_all_versions.include?(version)
    end
    connection.schema_cache.clear!
  end

  def migrate_up!
    context = migration_context
    MIGRATION_VERSIONS.each do |version|
      context.run(:up, version) unless context.get_all_versions.include?(version)
    end
    connection.schema_cache.clear!
  end

  def create_conversation(sender, recipient)
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    conversation
  end

  def insert_legacy_message(conversation:, sender:, body:)
    connection.select_value(<<~SQL.squish).to_i
      INSERT INTO forum_messages (
        forum_conversation_id, user_id, body, created_at, updated_at
      ) VALUES (
        #{conversation.id},
        #{sender.id},
        #{connection.quote(body)},
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      RETURNING id
    SQL
  end

  def queue_count(message_id)
    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM forum_message_revision_backfill_queue
      WHERE forum_message_id = #{Integer(message_id)}
    SQL
  end

  # A real database trigger creates a new old-process message from inside the
  # first revision batch. This deterministically proves that a migration run is
  # bounded by its starting watermark instead of chasing a moving write tail.
  def install_moving_tail_trigger(source_message_id:, conversation:, sender:, body:)
    drop_moving_tail_trigger
    connection.execute <<~SQL
      CREATE FUNCTION test_forum_revision_create_moving_tail()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.forum_message_id = #{Integer(source_message_id)} THEN
          INSERT INTO forum_messages (
            forum_conversation_id, user_id, body, created_at, updated_at
          ) VALUES (
            #{conversation.id},
            #{sender.id},
            #{connection.quote(body)},
            CURRENT_TIMESTAMP,
            CURRENT_TIMESTAMP
          );
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER test_forum_revision_create_moving_tail
      AFTER INSERT ON forum_message_revisions
      FOR EACH ROW
      EXECUTE FUNCTION test_forum_revision_create_moving_tail();
    SQL
  end

  def drop_moving_tail_trigger
    return unless connection.table_exists?(:forum_message_revisions)

    connection.execute <<~SQL
      DROP TRIGGER IF EXISTS test_forum_revision_create_moving_tail ON forum_message_revisions;
      DROP FUNCTION IF EXISTS test_forum_revision_create_moving_tail();
    SQL
  end

  def assert_all_contract_constraints_validated
    names = ContractCommunitySelfServiceFoundation::CHECK_CONSTRAINTS.values.flatten
    invalid = connection.select_values(<<~SQL.squish)
      SELECT constraint_names.name
      FROM unnest(ARRAY[#{names.map { |name| connection.quote(name) }.join(',')}])
        AS constraint_names(name)
      LEFT JOIN pg_constraint ON pg_constraint.conname = constraint_names.name
      WHERE pg_constraint.oid IS NULL OR pg_constraint.convalidated = FALSE
    SQL
    assert_empty invalid
  end

  def assert_all_concurrent_indexes_valid
    names = [
      AddCommunitySelfServiceFoundation::REPORT_DEDUPE_INDEX,
      AddCommunitySelfServiceFoundation::MESSAGE_ATTACHMENT_INDEX
    ]
    invalid = connection.select_values(<<~SQL.squish)
      SELECT index_names.name
      FROM unnest(ARRAY[#{names.map { |name| connection.quote(name) }.join(',')}])
        AS index_names(name)
      LEFT JOIN pg_class AS index_relations ON index_relations.relname = index_names.name
      LEFT JOIN pg_index ON pg_index.indexrelid = index_relations.oid
      WHERE pg_index.indexrelid IS NULL OR pg_index.indisvalid = FALSE
    SQL
    assert_empty invalid
  end

  def assert_not_null_contract
    ContractCommunitySelfServiceFoundation::NOT_NULL_COLUMNS.each do |table, column, _name|
      schema_column = connection.columns(table).find { |item| item.name == column.to_s }
      assert_not_nil schema_column
      assert_equal false, schema_column.null, "#{table}.#{column} must be NOT NULL"
    end
  end

  def reset_feature_models!
    [
      Community::Message,
      Community::MessageRevision,
      Community::MessageDraft,
      Community::PostAttachment,
      Community::ProfilePost,
      Community::ProfilePostComment,
      Community::Report,
      Community::ReportEvidence
    ].each(&:reset_column_information)
  end

  def connection
    ActiveRecord::Base.connection
  end
end
