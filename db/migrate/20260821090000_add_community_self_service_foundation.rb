# frozen_string_literal: true

class AddCommunitySelfServiceFoundation < ActiveRecord::Migration[8.1]
  REVIEW_PERMISSION = "forum.conversations.reports.review"

  def up
    add_column :forum_reports, :dedupe_key, :string, limit: 64
    add_index :forum_reports,
      :dedupe_key,
      unique: true,
      where: "dedupe_key IS NOT NULL AND status = 'pending'",
      name: "idx_forum_reports_pending_dedupe"
    add_check_constraint :forum_reports,
      "dedupe_key IS NULL OR dedupe_key ~ '^[0-9a-f]{64}$'",
      name: "forum_reports_dedupe_key_format"

    create_table :forum_report_evidences do |t|
      t.references :forum_report, null: false, foreign_key: true, index: { unique: true }
      t.string :subject_type, null: false
      t.bigint :subject_id, null: false
      t.integer :subject_revision, null: false, default: 1
      t.text :encrypted_snapshot, null: false
      t.string :content_digest, null: false, limit: 64
      t.datetime :captured_at, null: false
      t.timestamps
    end
    add_index :forum_report_evidences,
      %i[subject_type subject_id],
      name: "idx_forum_report_evidences_subject"
    add_check_constraint :forum_report_evidences,
      "subject_revision > 0",
      name: "forum_report_evidences_positive_revision"
    add_check_constraint :forum_report_evidences,
      "content_digest ~ '^[0-9a-f]{64}$'",
      name: "forum_report_evidences_digest_format"

    add_column :forum_messages, :revision, :integer, null: false, default: 1
    add_check_constraint :forum_messages, "revision > 0", name: "forum_messages_positive_revision"
    create_table :forum_message_revisions do |t|
      t.references :forum_message,
        null: false,
        foreign_key: { on_delete: :cascade }
      t.references :editor, null: false, foreign_key: { to_table: :users }
      t.integer :revision, null: false
      t.text :encrypted_body, null: false
      t.string :content_digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index :forum_message_revisions,
      %i[forum_message_id revision],
      unique: true,
      name: "idx_forum_message_revisions_unique"
    add_check_constraint :forum_message_revisions,
      "revision > 0",
      name: "forum_message_revisions_positive_revision"
    add_check_constraint :forum_message_revisions,
      "content_digest ~ '^[0-9a-f]{64}$'",
      name: "forum_message_revisions_digest_format"
    add_column :forum_message_drafts, :attachment_ids, :jsonb, null: false, default: []

    add_reference :forum_post_attachments,
      :forum_message,
      foreign_key: true,
      index: true
    add_check_constraint :forum_post_attachments,
      "NOT (forum_post_id IS NOT NULL AND forum_message_id IS NOT NULL)",
      name: "forum_post_attachments_single_parent"

    add_column :forum_profile_posts, :edited_at, :datetime
    add_column :forum_profile_posts, :revision, :integer, null: false, default: 1
    add_check_constraint :forum_profile_posts,
      "revision > 0",
      name: "forum_profile_posts_positive_revision"
    add_column :forum_profile_post_comments, :edited_at, :datetime
    add_column :forum_profile_post_comments, :revision, :integer, null: false, default: 1
    add_check_constraint :forum_profile_post_comments,
      "revision > 0",
      name: "forum_profile_post_comments_positive_revision"

    create_report_evidence_immutability
    create_message_revision_immutability
    upsert_review_permission
  end

  def down
    execute "DROP TRIGGER IF EXISTS forum_report_evidences_immutable ON forum_report_evidences"
    execute "DROP FUNCTION IF EXISTS forum_report_evidences_reject_change()"
    execute "DROP TRIGGER IF EXISTS forum_message_revisions_immutable ON forum_message_revisions"
    execute "DROP FUNCTION IF EXISTS forum_message_revisions_reject_change()"

    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key = #{connection.quote(REVIEW_PERMISSION)})
    SQL
    execute "DELETE FROM permissions WHERE key = #{connection.quote(REVIEW_PERMISSION)}"

    remove_check_constraint :forum_profile_post_comments, name: "forum_profile_post_comments_positive_revision"
    remove_column :forum_profile_post_comments, :revision
    remove_column :forum_profile_post_comments, :edited_at
    remove_check_constraint :forum_profile_posts, name: "forum_profile_posts_positive_revision"
    remove_column :forum_profile_posts, :revision
    remove_column :forum_profile_posts, :edited_at

    remove_check_constraint :forum_post_attachments, name: "forum_post_attachments_single_parent"
    remove_reference :forum_post_attachments, :forum_message, foreign_key: true

    drop_table :forum_message_revisions
    remove_column :forum_message_drafts, :attachment_ids
    remove_check_constraint :forum_messages, name: "forum_messages_positive_revision"
    remove_column :forum_messages, :revision

    drop_table :forum_report_evidences
    remove_check_constraint :forum_reports, name: "forum_reports_dedupe_key_format"
    remove_index :forum_reports, name: "idx_forum_reports_pending_dedupe"
    remove_column :forum_reports, :dedupe_key
  end

  private

  def create_report_evidence_immutability
    execute <<~SQL
      CREATE FUNCTION forum_report_evidences_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum_report_evidences is append-only';
      END;
      $$;

      CREATE TRIGGER forum_report_evidences_immutable
      BEFORE UPDATE OR DELETE ON forum_report_evidences
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_evidences_reject_change();
    SQL
  end

  def create_message_revision_immutability
    execute <<~SQL
      CREATE FUNCTION forum_message_revisions_reject_change()
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

      CREATE TRIGGER forum_message_revisions_immutable
      BEFORE UPDATE OR DELETE ON forum_message_revisions
      FOR EACH ROW
      EXECUTE FUNCTION forum_message_revisions_reject_change();
    SQL
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
