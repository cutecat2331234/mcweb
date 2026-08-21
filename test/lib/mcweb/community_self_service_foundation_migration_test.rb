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
    reset_foundation!
  end

  teardown do
    reset_foundation!
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
    assert_operator finalized.fetch(:watermark), :>=, moving_tail.id
    assert_equal 0, finalized.fetch(:tail_inserted)
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

  test "expand and contract migrations verify definitions and resume every committed phase" do
    migrate_down!

    expand = AddCommunitySelfServiceFoundation.new
    expand.migrate(:up)
    connection.execute(<<~SQL)
      ALTER TABLE forum_messages
      VALIDATE CONSTRAINT forum_messages_positive_revision
    SQL
    assert_equal true,
      boolean_value(check_constraint_row(:forum_messages, "forum_messages_positive_revision").fetch("validated"))

    # This is an actual second invocation of the complete non-transactional up,
    # including its concurrent indexes and every trigger/function definition.
    expand.migrate(:up)
    assert_equal true,
      boolean_value(check_constraint_row(:forum_messages, "forum_messages_positive_revision").fetch("validated"))

    connection.execute(<<~SQL)
      ALTER TABLE forum_messages
      DROP CONSTRAINT forum_messages_positive_revision;
      ALTER TABLE forum_messages
      ADD CONSTRAINT forum_messages_positive_revision CHECK (revision >= 0) NOT VALID;
    SQL
    error = assert_raises(ActiveRecord::MigrationError) { expand.migrate(:up) }
    assert_match(/unexpected definition/, error.message)
    connection.execute(<<~SQL)
      ALTER TABLE forum_messages
      DROP CONSTRAINT forum_messages_positive_revision
    SQL
    expand.migrate(:up)

    BackfillCommunityMessageRevisions.new.migrate(:up)
    interrupted_contract = Class.new(ContractCommunitySelfServiceFoundation) do
      def change_column_null(table, column, null, *args, **kwargs)
        if table.to_sym == :forum_messages && column.to_sym == :revision && !defined?(@failed_once)
          @failed_once = true
          raise "injected failure after CHECK validation"
        end

        super
      end
    end.new

    failure = assert_raises(RuntimeError) { interrupted_contract.migrate(:up) }
    assert_equal "injected failure after CHECK validation", failure.message
    helper = check_constraint_row(:forum_messages, "forum_messages_revision_not_null")
    assert_equal true, boolean_value(helper.fetch("validated"))
    assert_equal true, connection.columns(:forum_messages).find { |column| column.name == "revision" }.null

    ContractCommunitySelfServiceFoundation.new.migrate(:up)
    assert_equal false, connection.columns(:forum_messages).find { |column| column.name == "revision" }.null
    assert_nil check_constraint_row(:forum_messages, "forum_messages_revision_not_null")

    # A complete repeat after the helper was removed proves that the contract
    # migration does not rely on an artifact from the first successful run.
    ContractCommunitySelfServiceFoundation.new.migrate(:up)
    assert_all_contract_constraints_validated
    assert_not_null_contract

    # Record the versions through the real migration context; this invokes all
    # three complete up methods once more and leaves teardown in a normal state.
    migrate_up!
  end

  test "legacy body updates queue exact snapshots and cannot silently skip a revision" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    message = conversation.messages.create!(user: sender, body: "Initial legacy-edit body")

    legacy_update(message.id, "First legacy process edit")
    assert_equal 2, message.reload.revision
    assert_equal "First legacy process edit", message.body
    assert_queue_snapshot(message, revision: 2, body: message.body)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      legacy_update(message.id, "Second edit before snapshot")
    end
    assert_match(/pending revision snapshot/, error.message)
    message.reload
    assert_equal [ 2, "First legacy process edit" ], [ message.revision, message.body ]

    first_tail = Mcweb::Migrations::CommunityMessageRevisionBackfill.new.call_queue(limit: 10)
    assert_equal 1, first_tail.fetch(:inserted)
    assert_equal 0, queue_count(message.id)

    legacy_update(message.id, "Second legacy process edit")
    second_tail = Mcweb::Migrations::CommunityMessageRevisionBackfill.new.call_queue(limit: 10)
    assert_equal 1, second_tail.fetch(:inserted)
    assert_equal [ 1, 2, 3 ], message.revisions.order(:revision).pluck(:revision)
    assert_equal [
      "Initial legacy-edit body",
      "First legacy process edit",
      "Second legacy process edit"
    ], message.revisions.order(:revision).map(&:body)

    finalized = Mcweb::Migrations::CommunityMessageRevisionContract.new.call
    assert_equal true, finalized.fetch(:finalized)

    preseeded = conversation.messages.create!(user: sender, body: "Preseeded revision source")
    future_body = "Preseeded revision must not bypass same-transaction evidence"
    Community::MessageRevision.create!(
      message: preseeded,
      editor: sender,
      revision: 2,
      body: future_body,
      content_digest: Digest::SHA256.hexdigest(future_body)
    )
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true) do
        legacy_update(preseeded.id, future_body)
      end
    end
    preseeded.reload
    assert_equal [ 1, "Preseeded revision source" ], [ preseeded.revision, preseeded.body ]
    assert_equal 0, queue_count(preseeded.id)

    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction(requires_new: true) do
        legacy_update(message.id, "Legacy edit after the gate")
      end
    end
    message.reload
    assert_equal [ 3, "Second legacy process edit" ], [ message.revision, message.body ]
    assert_equal 0, queue_count(message.id)

    current = Community::EditMessage.call(
      user: sender,
      message: message,
      body: "Current application edit",
      expected_revision: 3
    )
    assert_predicate current, :success?, current.error
    assert_equal [ 1, 2, 3, 4 ], message.revisions.order(:revision).pluck(:revision)
    assert_equal 0, queue_count(message.id)
  end

  test "a mismatched revision digest never clears its queue or passes finalization" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    message = conversation.messages.create!(user: sender, body: "Digest source")

    legacy_update(message.id, "Digest-sensitive legacy edit")
    mismatch = Community::MessageRevision.create!(
      message: message,
      editor: sender,
      revision: 2,
      body: "different snapshot",
      content_digest: "0" * 64
    )
    refute_predicate mismatch, :digest_valid?
    assert_queue_snapshot(message, revision: 2, body: "Digest-sensitive legacy edit")
    assert_equal 1, Mcweb::Migrations::CommunityMessageRevisionBackfill.new.missing_count
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?

    assert_raises(ActiveRecord::StatementInvalid) do
      legacy_update(message.id, "Must not skip corrupt revision two")
    end
    message.reload
    assert_equal [ 2, "Digest-sensitive legacy edit" ], [ message.revision, message.body ]
  end

  test "a large preflight is outside the hard-capped final lock tail" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    ids = insert_legacy_messages(conversation: conversation, sender: sender, count: 75)
    assert_equal 75, queue_count_for(ids)

    result = Mcweb::Migrations::CommunityMessageRevisionContract.new(
      batch_size: 11,
      tail_limit: 2
    ).call

    assert_equal true, result.fetch(:finalized)
    assert_equal 75, result.fetch(:preflight_inserted)
    assert_equal 0, result.fetch(:tail_inserted)
    assert_equal 0, queue_count_for(ids)
    assert_contract_trigger_metadata
  end

  test "an unresolved tail over the limit fails fast and is safe to rerun" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    ids = insert_legacy_messages(conversation: conversation, sender: sender, count: 3)
    ids.each_with_index do |message_id, index|
      message = Community::Message.find(message_id)
      Community::MessageRevision.create!(
        message: message,
        editor: sender,
        revision: 1,
        body: "wrong tail #{index}",
        content_digest: "0" * 64
      )
    end

    error = assert_raises(Mcweb::Migrations::CommunityMessageRevisionBackfill::TailLimitExceeded) do
      Mcweb::Migrations::CommunityMessageRevisionContract.new(tail_limit: 2).call
    end
    assert_equal 2, error.limit
    assert_equal 3, queue_count_for(ids)
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?

    # The failed gate is fully rollback-safe. Removing the intentionally corrupt
    # fixture through the governed parent lifecycle lets an ordinary retry close.
    ids.each { |id| Community::Message.with_discarded.find(id).destroy! }
    retried = Mcweb::Migrations::CommunityMessageRevisionContract.new(tail_limit: 2).call
    assert_equal true, retried.fetch(:finalized)
  end

  test "a concurrent old writer after the high watermark is captured as a bounded tail" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    preflight_complete = Queue.new
    allow_final_lock = Queue.new
    finalizer_result = Queue.new
    contract_class = Class.new(Mcweb::Migrations::CommunityMessageRevisionContract) do
      define_method(:initialize) do |preflight_complete:, allow_final_lock:|
        @test_preflight_complete = preflight_complete
        @test_allow_final_lock = allow_final_lock
        super()
      end

      private

      def before_write_lock(_preflight)
        @test_preflight_complete << true
        @test_allow_final_lock.pop
      end
    end

    finalizer = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        finalizer_result << contract_class.new(
          preflight_complete: preflight_complete,
          allow_final_lock: allow_final_lock
        ).call
      rescue StandardError => e
        finalizer_result << e
      end
    end
    preflight_complete.pop
    late_id = insert_legacy_message(
      conversation: conversation,
      sender: sender,
      body: "Concurrent legacy writer"
    )
    allow_final_lock << true
    finalizer.join

    result = finalizer_result.pop
    raise result if result.is_a?(Exception)

    assert_equal true, result.fetch(:finalized)
    assert_equal 1, result.fetch(:tail_inserted)
    assert Community::MessageRevision.exists?(forum_message_id: late_id, revision: 1)
    assert_equal 0, queue_count(late_id)
  ensure
    allow_final_lock << true if finalizer&.alive?
    finalizer&.join
  end

  test "a writer holding the table makes the final lock timeout without partial contract state" do
    reset_foundation!
    lock_ready = Queue.new
    release_lock = Queue.new
    locker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do |locker_connection|
        locker_connection.transaction do
          locker_connection.execute("LOCK TABLE forum_messages IN ROW EXCLUSIVE MODE")
          lock_ready << true
          release_lock.pop
        end
      end
    end
    lock_ready.pop
    original_timeout = connection.select_value("SHOW statement_timeout")
    lock_error = assert_raises(ActiveRecord::StatementInvalid) do
      Mcweb::Migrations::CommunityMessageRevisionContract.new(
        statement_timeout: "2s",
        lock_timeout: "100ms"
      ).call
    end
    assert_equal "55P03", sqlstate(lock_error)
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?
    assert_equal original_timeout, connection.select_value("SHOW statement_timeout")

    release_lock << true
    locker.join
    assert_equal true, Mcweb::Migrations::CommunityMessageRevisionContract.new.call.fetch(:finalized)
  ensure
    release_lock << true if locker&.alive?
    locker&.join
  end

  test "a statement timeout restores the session and allows a clean retry" do
    reset_foundation!
    sender = create_user(forum_trust_level_override: 1)
    recipient = create_user(forum_trust_level_override: 1)
    conversation = create_conversation(sender, recipient)
    message_id = insert_legacy_message(
      conversation: conversation,
      sender: sender,
      body: "Statement timeout candidate"
    )
    message = Community::Message.find(message_id)
    original_timeout = connection.select_value("SHOW statement_timeout")
    blocker_ready = Queue.new
    release_blocker = Queue.new
    blocker = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        Community::MessageRevision.transaction do
          Community::MessageRevision.create!(
            message: message,
            editor: sender,
            revision: 1,
            body: message.body,
            content_digest: Digest::SHA256.hexdigest(message.body)
          )
          blocker_ready << true
          release_blocker.pop
        end
      end
    end
    blocker_ready.pop

    error = assert_raises(ActiveRecord::StatementInvalid) do
      Mcweb::Migrations::CommunityMessageRevisionContract.new(
        statement_timeout: "100ms",
        lock_timeout: "2s"
      ).call
    end
    assert_equal "57014", sqlstate(error)
    assert_equal original_timeout, connection.select_value("SHOW statement_timeout")

    release_blocker << true
    blocker.join
    retried = Mcweb::Migrations::CommunityMessageRevisionContract.new.call
    assert_equal true, retried.fetch(:finalized)

  ensure
    release_blocker << true if blocker&.alive?
    blocker&.join
  end

  test "finalization rejects a disabled non-deferred or wrong-function trigger" do
    reset_foundation!
    connection.execute("ALTER TABLE forum_messages DISABLE TRIGGER forum_messages_queue_revision_backfill")
    protocol_error = assert_raises(RuntimeError) do
      Mcweb::Migrations::CommunityMessageRevisionContract.new.call
    end
    assert_match(/capture protocol is missing or altered/, protocol_error.message)
    connection.execute("ALTER TABLE forum_messages ENABLE TRIGGER forum_messages_queue_revision_backfill")

    assert_equal true, Mcweb::Migrations::CommunityMessageRevisionContract.new.call.fetch(:finalized)
    assert_contract_trigger_metadata

    connection.execute("ALTER TABLE forum_messages DISABLE TRIGGER forum_messages_require_current_revision")
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?
    connection.execute(<<~SQL)
      DROP TRIGGER forum_messages_require_current_revision ON forum_messages;
      CREATE OR REPLACE FUNCTION test_forum_messages_wrong_revision_contract()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$ BEGIN RETURN NEW; END; $$;
      CREATE TRIGGER forum_messages_require_current_revision
      AFTER INSERT OR UPDATE OF body, revision ON forum_messages
      FOR EACH ROW
      EXECUTE FUNCTION test_forum_messages_wrong_revision_contract();
    SQL
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?

    repaired = Mcweb::Migrations::CommunityMessageRevisionContract.new.call
    assert_equal true, repaired.fetch(:finalized)
    assert_contract_trigger_metadata

    connection.execute(<<~SQL)
      CREATE OR REPLACE FUNCTION forum_messages_require_current_revision()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$ BEGIN RETURN NEW; END; $$
    SQL
    refute Mcweb::Migrations::CommunityMessageRevisionContract.new.finalized?
    assert_equal true, Mcweb::Migrations::CommunityMessageRevisionContract.new.call.fetch(:finalized)
    assert_contract_trigger_metadata
  ensure
    if connection.table_exists?(:forum_messages)
      connection.execute("DROP FUNCTION IF EXISTS test_forum_messages_wrong_revision_contract()")
    end
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

  def reset_foundation!
    migrate_down!
    migrate_up!
    reset_feature_models!
  end

  def create_conversation(sender, recipient)
    conversation = Community::Conversation.create!
    conversation.participants.create!(user: sender)
    conversation.participants.create!(user: recipient)
    conversation
  end

  def insert_legacy_message(conversation:, sender:, body:, connection: nil)
    database = connection || self.connection
    database.select_value(<<~SQL.squish).to_i
      INSERT INTO forum_messages (
        forum_conversation_id, user_id, body, created_at, updated_at
      ) VALUES (
        #{conversation.id},
        #{sender.id},
        #{database.quote(body)},
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      RETURNING id
    SQL
  end

  def insert_legacy_messages(conversation:, sender:, count:)
    prefix = "Legacy bulk #{SecureRandom.hex(6)} row "
    connection.select_values(<<~SQL.squish).map(&:to_i)
      INSERT INTO forum_messages (
        forum_conversation_id, user_id, body, created_at, updated_at
      )
      SELECT
        #{conversation.id},
        #{sender.id},
        #{connection.quote(prefix)} || rows.number::text,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      FROM generate_series(1, #{Integer(count)}) AS rows(number)
      RETURNING id
    SQL
  end

  def legacy_update(message_id, body)
    connection.execute(<<~SQL.squish)
      UPDATE forum_messages
      SET body = #{connection.quote(body)},
          updated_at = CURRENT_TIMESTAMP
      WHERE id = #{Integer(message_id)}
    SQL
  end

  def queue_count(message_id)
    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM forum_message_revision_backfill_queue
      WHERE forum_message_id = #{Integer(message_id)}
    SQL
  end

  def queue_count_for(message_ids)
    return 0 if message_ids.empty?

    connection.select_value(<<~SQL.squish).to_i
      SELECT COUNT(*)
      FROM forum_message_revision_backfill_queue
      WHERE forum_message_id IN (#{message_ids.map { |id| Integer(id) }.join(',')})
    SQL
  end

  def assert_queue_snapshot(message, revision:, body:)
    row = connection.select_one(<<~SQL.squish)
      SELECT revision, body_digest
      FROM forum_message_revision_backfill_queue
      WHERE forum_message_id = #{Integer(message.id)}
        AND revision = #{Integer(revision)}
    SQL
    assert_not_nil row
    assert_equal revision, row.fetch("revision").to_i
    assert_equal Digest::SHA256.hexdigest(body), row.fetch("body_digest")
  end

  def check_constraint_row(table, name)
    connection.select_one(<<~SQL.squish)
      SELECT
        constraints.convalidated AS validated,
        pg_get_expr(constraints.conbin, constraints.conrelid) AS expression
      FROM pg_constraint AS constraints
      INNER JOIN pg_class AS tables
        ON tables.oid = constraints.conrelid
      INNER JOIN pg_namespace AS namespaces
        ON namespaces.oid = tables.relnamespace
      WHERE constraints.contype = 'c'
        AND namespaces.nspname = current_schema()
        AND tables.relname = #{connection.quote(table.to_s)}
        AND constraints.conname = #{connection.quote(name.to_s)}
      LIMIT 1
    SQL
  end

  def boolean_value(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end

  def sqlstate(error)
    current = error
    while current
      if current.respond_to?(:result) && current.result
        return current.result.error_field(PG::Result::PG_DIAG_SQLSTATE)
      end

      current = current.cause
    end
    nil
  end

  def assert_contract_trigger_metadata
    row = connection.select_one(<<~SQL.squish)
      SELECT
        triggers.tgenabled,
        triggers.tgtype,
        triggers.tgdeferrable,
        triggers.tginitdeferred,
        (triggers.tgconstraint <> 0) AS constraint_trigger,
        procedures.proname AS function_name,
        procedure_namespaces.nspname AS function_schema,
        current_schema() AS current_schema,
        pg_get_triggerdef(triggers.oid, TRUE) AS definition,
        (
          SELECT string_agg(attributes.attname, ',' ORDER BY selected.ordinality)
          FROM unnest(triggers.tgattr::smallint[]) WITH ORDINALITY AS selected(attnum, ordinality)
          INNER JOIN pg_attribute AS attributes
            ON attributes.attrelid = triggers.tgrelid
           AND attributes.attnum = selected.attnum
        ) AS update_columns
      FROM pg_trigger AS triggers
      INNER JOIN pg_class AS tables
        ON tables.oid = triggers.tgrelid
      INNER JOIN pg_namespace AS table_namespaces
        ON table_namespaces.oid = tables.relnamespace
      INNER JOIN pg_proc AS procedures
        ON procedures.oid = triggers.tgfoid
      INNER JOIN pg_namespace AS procedure_namespaces
        ON procedure_namespaces.oid = procedures.pronamespace
      WHERE table_namespaces.nspname = current_schema()
        AND tables.relname = 'forum_messages'
        AND triggers.tgname = 'forum_messages_require_current_revision'
        AND NOT triggers.tgisinternal
    SQL
    assert_not_nil row
    assert_equal "O", row.fetch("tgenabled")
    assert_equal 21, row.fetch("tgtype").to_i
    assert_equal true, boolean_value(row.fetch("tgdeferrable"))
    assert_equal true, boolean_value(row.fetch("tginitdeferred"))
    assert_equal true, boolean_value(row.fetch("constraint_trigger"))
    assert_equal "body,revision", row.fetch("update_columns")
    assert_equal "forum_messages_require_current_revision", row.fetch("function_name")
    assert_equal row.fetch("current_schema"), row.fetch("function_schema")
    assert_match(/DEFERRABLE INITIALLY DEFERRED/, row.fetch("definition"))
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
    names = ContractCommunitySelfServiceFoundation::CHECK_CONSTRAINTS.values.flat_map(&:keys)
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
      Community::Post,
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
