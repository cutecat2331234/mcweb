# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/check_constraint_contract")

# Expand phase for community self-service.
#
# Existing-table indexes are concurrent, constraints start NOT VALID, and no
# message encryption runs here. The queue triggers cover messages created by an
# old web process until the new dual-writing application has been deployed and
# the explicit post-deploy contract gate is finalized.
class AddCommunitySelfServiceFoundation < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::CheckConstraintContract

  disable_ddl_transaction!

  REVIEW_PERMISSION = "forum.conversations.reports.review"
  REPORT_DEDUPE_INDEX = "idx_forum_reports_pending_dedupe"
  MESSAGE_ATTACHMENT_INDEX = "index_forum_post_attachments_on_forum_message_id"
  MESSAGE_QUEUE_INDEX = "idx_forum_message_revision_backfill_queue_unique"
  LEGACY_MESSAGE_QUEUE_INDEX = "idx_forum_message_revision_backfill_queue"
  CHECK_CONSTRAINTS = Mcweb::Migrations::CheckConstraintContract::FEATURE_CHECK_CONSTRAINTS

  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")
    expand_reports
    expand_report_evidence
    expand_message_revisions
    expand_message_attachments
    expand_profile_wall
    create_report_evidence_immutability
    create_message_revision_immutability
    create_message_revision_queue_triggers
    upsert_review_permission
  end

  def down
    drop_message_revision_contract
    drop_message_revision_queue_triggers
    drop_immutability_triggers
    contract_profile_wall
    contract_message_attachments
    contract_message_revisions
    contract_report_evidence
    contract_reports
    # The permission and grants are deliberately retained: rollback cannot
    # prove whether this migration, an earlier release, or a plugin created them.
  end

  private

  def expand_reports
    add_column :forum_reports, :dedupe_key, :string, limit: 64, if_not_exists: true
    ensure_concurrent_index(
      :forum_reports,
      :dedupe_key,
      unique: true,
      where: "dedupe_key IS NOT NULL AND status = 'pending'",
      name: REPORT_DEDUPE_INDEX
    )
    ensure_feature_check(:forum_reports, "forum_reports_dedupe_key_format")
  end

  def expand_report_evidence
    unless table_exists?(:forum_report_evidences)
      create_table :forum_report_evidences do |t|
        t.bigint :forum_report_id, null: false
        t.string :subject_type, null: false
        t.bigint :subject_id, null: false
        t.integer :subject_revision, null: false, default: 1
        t.text :encrypted_snapshot, null: false
        t.string :content_digest, null: false, limit: 64
        t.datetime :captured_at, null: false
        t.timestamps
      end
    end

    add_index :forum_report_evidences,
      :forum_report_id,
      unique: true,
      name: "index_forum_report_evidences_on_forum_report_id",
      if_not_exists: true
    add_index :forum_report_evidences,
      %i[subject_type subject_id],
      name: "idx_forum_report_evidences_subject",
      if_not_exists: true
    add_foreign_key :forum_report_evidences,
      :forum_reports,
      column: :forum_report_id,
      validate: false,
      if_not_exists: true
    ensure_feature_check(:forum_report_evidences, "forum_report_evidences_positive_revision")
    ensure_feature_check(:forum_report_evidences, "forum_report_evidences_digest_format")
  end

  def expand_message_revisions
    add_column :forum_messages,
      :revision,
      :integer,
      default: 1,
      if_not_exists: true
    ensure_feature_check(:forum_messages, "forum_messages_positive_revision")

    unless table_exists?(:forum_message_revisions)
      create_table :forum_message_revisions do |t|
        t.bigint :forum_message_id, null: false
        t.bigint :editor_id, null: false
        t.integer :revision, null: false
        t.text :encrypted_body, null: false
        t.string :content_digest, null: false, limit: 64
        t.datetime :created_at, null: false
      end
    end
    unless table_exists?(:forum_message_revision_backfill_queue)
      create_table :forum_message_revision_backfill_queue, id: false do |t|
        t.bigint :forum_message_id, null: false
        t.integer :revision
        t.string :body_digest, limit: 64
        t.datetime :queued_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      end
    end
    add_column :forum_message_revision_backfill_queue,
      :revision,
      :integer,
      if_not_exists: true
    add_column :forum_message_revision_backfill_queue,
      :body_digest,
      :string,
      limit: 64,
      if_not_exists: true
    backfill_message_revision_queue_metadata

    add_index :forum_message_revisions,
      :forum_message_id,
      name: "index_forum_message_revisions_on_forum_message_id",
      if_not_exists: true
    add_index :forum_message_revisions,
      :editor_id,
      name: "index_forum_message_revisions_on_editor_id",
      if_not_exists: true
    add_index :forum_message_revisions,
      %i[forum_message_id revision],
      unique: true,
      name: "idx_forum_message_revisions_unique",
      if_not_exists: true
    remove_legacy_message_queue_index
    add_index :forum_message_revision_backfill_queue,
      %i[forum_message_id revision],
      unique: true,
      name: MESSAGE_QUEUE_INDEX,
      if_not_exists: true
    add_foreign_key :forum_message_revisions,
      :forum_messages,
      column: :forum_message_id,
      on_delete: :cascade,
      validate: false,
      if_not_exists: true
    add_foreign_key :forum_message_revisions,
      :users,
      column: :editor_id,
      validate: false,
      if_not_exists: true
    add_foreign_key :forum_message_revision_backfill_queue,
      :forum_messages,
      column: :forum_message_id,
      on_delete: :cascade,
      validate: false,
      if_not_exists: true
    ensure_feature_check(:forum_message_revisions, "forum_message_revisions_positive_revision")
    ensure_feature_check(:forum_message_revisions, "forum_message_revisions_digest_format")
    ensure_feature_check(
      :forum_message_revision_backfill_queue,
      "forum_message_revision_queue_positive_revision"
    )
    ensure_feature_check(
      :forum_message_revision_backfill_queue,
      "forum_message_revision_queue_digest_format"
    )

    add_column :forum_message_drafts,
      :attachment_ids,
      :jsonb,
      default: [],
      if_not_exists: true
  end

  def expand_message_attachments
    add_column :forum_post_attachments,
      :forum_message_id,
      :bigint,
      if_not_exists: true
    ensure_concurrent_index(
      :forum_post_attachments,
      :forum_message_id,
      name: MESSAGE_ATTACHMENT_INDEX
    )
    add_foreign_key :forum_post_attachments,
      :forum_messages,
      column: :forum_message_id,
      validate: false,
      if_not_exists: true
    ensure_feature_check(:forum_post_attachments, "forum_post_attachments_single_parent")
  end

  def expand_profile_wall
    add_column :forum_posts,
      :revision,
      :integer,
      default: 1,
      if_not_exists: true
    ensure_feature_check(:forum_posts, "forum_posts_positive_revision")

    add_column :forum_profile_posts, :edited_at, :datetime, if_not_exists: true
    add_column :forum_profile_posts,
      :revision,
      :integer,
      default: 1,
      if_not_exists: true
    ensure_feature_check(:forum_profile_posts, "forum_profile_posts_positive_revision")

    add_column :forum_profile_post_comments, :edited_at, :datetime, if_not_exists: true
    add_column :forum_profile_post_comments,
      :revision,
      :integer,
      default: 1,
      if_not_exists: true
    ensure_feature_check(:forum_profile_post_comments, "forum_profile_post_comments_positive_revision")
  end

  def contract_profile_wall
    remove_check_constraint :forum_profile_post_comments,
      name: "forum_profile_post_comments_positive_revision",
      if_exists: true
    remove_column :forum_profile_post_comments, :revision, if_exists: true
    remove_column :forum_profile_post_comments, :edited_at, if_exists: true
    remove_check_constraint :forum_profile_posts,
      name: "forum_profile_posts_positive_revision",
      if_exists: true
    remove_column :forum_profile_posts, :revision, if_exists: true
    remove_column :forum_profile_posts, :edited_at, if_exists: true
    remove_check_constraint :forum_posts,
      name: "forum_posts_positive_revision",
      if_exists: true
    remove_column :forum_posts, :revision, if_exists: true
  end

  def contract_message_attachments
    return unless column_exists?(:forum_post_attachments, :forum_message_id)

    remove_check_constraint :forum_post_attachments,
      name: "forum_post_attachments_single_parent",
      if_exists: true
    schedule_message_attachment_cleanup_for_rollback
    remove_foreign_key :forum_post_attachments,
      column: :forum_message_id,
      if_exists: true
    remove_index :forum_post_attachments,
      name: MESSAGE_ATTACHMENT_INDEX,
      algorithm: :concurrently,
      if_exists: true
    remove_column :forum_post_attachments, :forum_message_id
  end

  def contract_message_revisions
    drop_table :forum_message_revision_backfill_queue, if_exists: true
    drop_table :forum_message_revisions, if_exists: true
    remove_column :forum_message_drafts, :attachment_ids, if_exists: true
    remove_check_constraint :forum_messages,
      name: "forum_messages_positive_revision",
      if_exists: true
    remove_column :forum_messages, :revision, if_exists: true
  end

  def contract_report_evidence
    drop_table :forum_report_evidences, if_exists: true
  end

  def contract_reports
    remove_check_constraint :forum_reports,
      name: "forum_reports_dedupe_key_format",
      if_exists: true
    remove_index :forum_reports,
      name: REPORT_DEDUPE_INDEX,
      algorithm: :concurrently,
      if_exists: true
    remove_column :forum_reports, :dedupe_key, if_exists: true
  end

  # Failed CREATE INDEX CONCURRENTLY can leave an invalid artifact. Remove it
  # before retrying so IF NOT EXISTS cannot silently preserve an unusable index.
  def ensure_concurrent_index(table, columns, name:, **options)
    if invalid_index?(name)
      execute "DROP INDEX CONCURRENTLY IF EXISTS #{connection.quote_table_name(name)}"
    end

    add_index table,
      columns,
      **options,
      name: name,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def invalid_index?(name)
    ActiveModel::Type::Boolean.new.cast(
      select_value(<<~SQL.squish)
        SELECT EXISTS (
          SELECT 1
          FROM pg_index AS indexes
          INNER JOIN pg_class AS index_relations
            ON index_relations.oid = indexes.indexrelid
          INNER JOIN pg_namespace AS namespaces
            ON namespaces.oid = index_relations.relnamespace
          WHERE namespaces.nspname = current_schema()
            AND index_relations.relname = #{connection.quote(name)}
            AND indexes.indisvalid = FALSE
        )
      SQL
    )
  end

  def ensure_feature_check(table, name)
    expression = CHECK_CONSTRAINTS.fetch(table).fetch(name)
    ensure_named_check_constraint(table, name: name, expression: expression)
  end

  def backfill_message_revision_queue_metadata
    execute <<~SQL.squish
      UPDATE forum_message_revision_backfill_queue AS queue
      SET revision = messages.revision,
          body_digest = encode(
            digest(convert_to(messages.body, 'UTF8'), 'sha256'),
            'hex'
          )
      FROM forum_messages AS messages
      WHERE messages.id = queue.forum_message_id
        AND (queue.revision IS NULL OR queue.body_digest IS NULL)
    SQL
  end

  def remove_legacy_message_queue_index
    return unless index_name_exists?(:forum_message_revision_backfill_queue, LEGACY_MESSAGE_QUEUE_INDEX)

    remove_index :forum_message_revision_backfill_queue,
      name: LEGACY_MESSAGE_QUEUE_INDEX,
      algorithm: :concurrently
  end

  # Preserve blob ownership and quota accounting before rollback removes the
  # only relation that distinguishes a linked private-message attachment.
  def schedule_message_attachment_cleanup_for_rollback
    execute <<~SQL.squish
      UPDATE forum_uploads AS uploads
      SET status = 'cleanup_pending',
          expires_at = CURRENT_TIMESTAMP,
          cleanup_started_at = NULL,
          cleanup_error_code = NULL,
          cleanup_error_message = NULL,
          forum_post_id = NULL,
          updated_at = CURRENT_TIMESTAMP
      FROM forum_post_attachments AS attachments
      WHERE uploads.forum_post_attachment_id = attachments.id
        AND attachments.forum_message_id IS NOT NULL
        AND uploads.status <> 'cleaned'
    SQL
  end

  def create_report_evidence_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_report_evidences_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum_report_evidences is append-only';
      END;
      $$;

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'forum_report_evidences_immutable'
            AND tgrelid = 'forum_report_evidences'::regclass
        ) THEN
          CREATE TRIGGER forum_report_evidences_immutable
          BEFORE UPDATE OR DELETE ON forum_report_evidences
          FOR EACH ROW
          EXECUTE FUNCTION forum_report_evidences_reject_change();
        END IF;
      END;
      $$;
    SQL
  end

  def create_message_revision_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_message_revisions_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'DELETE' AND NOT EXISTS (
          SELECT 1 FROM forum_messages WHERE id = OLD.forum_message_id
        ) THEN
          RETURN OLD;
        END IF;

        RAISE EXCEPTION 'forum_message_revisions is immutable while its message exists';
      END;
      $$;

      DO $$
      BEGIN
        IF NOT EXISTS (
          SELECT 1 FROM pg_trigger
          WHERE tgname = 'forum_message_revisions_immutable'
            AND tgrelid = 'forum_message_revisions'::regclass
        ) THEN
          CREATE TRIGGER forum_message_revisions_immutable
          BEFORE UPDATE OR DELETE ON forum_message_revisions
          FOR EACH ROW
          EXECUTE FUNCTION forum_message_revisions_reject_change();
        END IF;
      END;
      $$;
    SQL
  end

  def create_message_revision_queue_triggers
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_messages_prepare_revision_update()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.body IS NOT DISTINCT FROM OLD.body
           AND NEW.revision IS NOT DISTINCT FROM OLD.revision THEN
          RETURN NEW;
        END IF;

        IF EXISTS (
          SELECT 1
          FROM forum_message_revision_backfill_queue
          WHERE forum_message_id = OLD.id
        ) THEN
          RAISE EXCEPTION 'forum message has a pending revision snapshot';
        END IF;

        IF NEW.body IS DISTINCT FROM OLD.body AND NEW.revision = OLD.revision THEN
          NEW.revision := OLD.revision + 1;
        END IF;

        IF NEW.revision <> OLD.revision + 1 THEN
          RAISE EXCEPTION 'forum message revision must advance by one';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION forum_messages_queue_revision_backfill()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        snapshot_digest text;
      BEGIN
        snapshot_digest := encode(
          digest(convert_to(NEW.body, 'UTF8'), 'sha256'),
          'hex'
        );
        INSERT INTO forum_message_revision_backfill_queue (
          forum_message_id,
          revision,
          body_digest,
          queued_at
        )
        VALUES (NEW.id, NEW.revision, snapshot_digest, CURRENT_TIMESTAMP)
        ON CONFLICT (forum_message_id, revision) DO NOTHING;
        IF NOT FOUND AND NOT EXISTS (
          SELECT 1
          FROM forum_message_revision_backfill_queue
          WHERE forum_message_id = NEW.id
            AND revision = NEW.revision
            AND body_digest = snapshot_digest
        ) THEN
          RAISE EXCEPTION 'forum message revision queue conflict';
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION forum_message_revisions_dequeue_backfill()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        DELETE FROM forum_message_revision_backfill_queue
        WHERE forum_message_id = NEW.forum_message_id
          AND revision = NEW.revision
          AND body_digest = NEW.content_digest;
        RETURN NEW;
      END;
      $$;

      DROP TRIGGER IF EXISTS forum_messages_prepare_revision_update ON forum_messages;
      CREATE TRIGGER forum_messages_prepare_revision_update
      BEFORE UPDATE OF body, revision ON forum_messages
      FOR EACH ROW
      EXECUTE FUNCTION forum_messages_prepare_revision_update();

      DROP TRIGGER IF EXISTS forum_messages_queue_revision_backfill ON forum_messages;
      CREATE TRIGGER forum_messages_queue_revision_backfill
      AFTER INSERT OR UPDATE OF body, revision ON forum_messages
      FOR EACH ROW
      EXECUTE FUNCTION forum_messages_queue_revision_backfill();

      DROP TRIGGER IF EXISTS forum_message_revisions_dequeue_backfill ON forum_message_revisions;
      CREATE TRIGGER forum_message_revisions_dequeue_backfill
      AFTER INSERT ON forum_message_revisions
      FOR EACH ROW
      EXECUTE FUNCTION forum_message_revisions_dequeue_backfill();
    SQL
  end

  def drop_message_revision_queue_triggers
    execute "DROP TRIGGER IF EXISTS forum_messages_prepare_revision_update ON forum_messages"
    execute "DROP TRIGGER IF EXISTS forum_messages_queue_revision_backfill ON forum_messages"
    if table_exists?(:forum_message_revisions)
      execute "DROP TRIGGER IF EXISTS forum_message_revisions_dequeue_backfill ON forum_message_revisions"
    end
    execute "DROP FUNCTION IF EXISTS forum_messages_prepare_revision_update()"
    execute "DROP FUNCTION IF EXISTS forum_messages_queue_revision_backfill()"
    execute "DROP FUNCTION IF EXISTS forum_message_revisions_dequeue_backfill()"
  end

  def drop_message_revision_contract
    execute "DROP TRIGGER IF EXISTS forum_messages_require_current_revision ON forum_messages"
    execute "DROP FUNCTION IF EXISTS forum_messages_require_current_revision()"
  end

  def drop_immutability_triggers
    if table_exists?(:forum_report_evidences)
      execute "DROP TRIGGER IF EXISTS forum_report_evidences_immutable ON forum_report_evidences"
    end
    execute "DROP FUNCTION IF EXISTS forum_report_evidences_reject_change()"
    if table_exists?(:forum_message_revisions)
      execute "DROP TRIGGER IF EXISTS forum_message_revisions_immutable ON forum_message_revisions"
    end
    execute "DROP FUNCTION IF EXISTS forum_message_revisions_reject_change()"
  end

  def upsert_review_permission
    execute <<~SQL.squish
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(REVIEW_PERMISSION)},
        'Review private-message reports',
        'forum',
        'Review reported private messages and explicitly reveal encrypted evidence',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO UPDATE SET
        name = EXCLUDED.name,
        category = EXCLUDED.category,
        description = EXCLUDED.description,
        updated_at = CURRENT_TIMESTAMP
    SQL

    execute <<~SQL.squish
      INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
      SELECT roles.id, permissions.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM roles
      CROSS JOIN permissions
      WHERE roles.key IN ('owner', 'super_admin')
        AND permissions.key = #{connection.quote(REVIEW_PERMISSION)}
      ON CONFLICT (role_id, permission_id) DO NOTHING
    SQL
  end
end
