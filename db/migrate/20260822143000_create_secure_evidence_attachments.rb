# frozen_string_literal: true

class CreateSecureEvidenceAttachments < ActiveRecord::Migration[8.1]
  EVENT_TRIGGER = "secure_evidence_attachment_events_immutable"
  EVENT_FUNCTION = "secure_evidence_attachment_events_reject_change"
  ATTACHMENT_TRIGGER = "secure_evidence_attachments_reject_delete"
  ATTACHMENT_FUNCTION = "secure_evidence_attachments_reject_delete"
  ATTACHMENT_UPDATE_TRIGGER = "secure_evidence_attachments_guard_update"
  ATTACHMENT_UPDATE_FUNCTION = "secure_evidence_attachments_guard_update"

  def up
    create_attachments
    create_events
    extend_uploads
    create_event_immutability
    create_attachment_delete_guard
    create_attachment_update_guard
  end

  def down
    prepare_uploads_for_rollback
    remove_upload_extension
    drop_event_immutability
    drop_attachment_delete_guard
    drop_attachment_update_guard
    drop_table :secure_evidence_attachment_events, if_exists: true
    drop_table :secure_evidence_attachments, if_exists: true
    restore_upload_kind_constraint
  end

  private

  def create_attachments
    create_table :secure_evidence_attachments do |t|
      t.string :public_id, null: false
      t.references :uploader, null: false, foreign_key: { to_table: :users }
      t.string :uploader_public_id_snapshot, null: false
      t.string :subject_key, null: false
      t.bigint :subject_id, null: false
      t.string :subject_public_id, null: false
      t.string :idempotency_key, null: false
      t.string :request_fingerprint, null: false, limit: 64
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false, limit: 64
      t.string :state, null: false, default: "pending"
      t.datetime :retention_until, null: false
      t.datetime :scanned_at
      t.datetime :quarantined_at
      t.datetime :purged_at
      t.timestamps
    end

    add_index :secure_evidence_attachments, :public_id, unique: true
    add_index :secure_evidence_attachments,
      %i[subject_key subject_id],
      name: "idx_secure_evidence_attachments_subject"
    add_index :secure_evidence_attachments,
      %i[state retention_until],
      name: "idx_secure_evidence_attachments_retention"
    add_index :secure_evidence_attachments,
      %i[uploader_id subject_key subject_id idempotency_key],
      unique: true,
      name: "idx_secure_evidence_attachments_idempotency"

    add_check_constraint :secure_evidence_attachments,
      "subject_key ~ '^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)+$'",
      name: "secure_evidence_attachments_subject_key_format"
    add_check_constraint :secure_evidence_attachments,
      "subject_id > 0",
      name: "secure_evidence_attachments_positive_subject_id"
    add_check_constraint :secure_evidence_attachments,
      "byte_size > 0 AND byte_size <= 10485760",
      name: "secure_evidence_attachments_bounded_size"
    add_check_constraint :secure_evidence_attachments,
      "sha256 ~ '^[0-9a-f]{64}$' AND request_fingerprint ~ '^[0-9a-f]{64}$'",
      name: "secure_evidence_attachments_digest_format"
    add_check_constraint :secure_evidence_attachments,
      "idempotency_key ~ '^[A-Za-z0-9:_-]{8,100}$'",
      name: "secure_evidence_attachments_idempotency_format"
    add_check_constraint :secure_evidence_attachments,
      "state IN ('pending', 'available', 'quarantined', 'purge_pending', 'purged')",
      name: "secure_evidence_attachments_valid_state"
    add_check_constraint :secure_evidence_attachments,
      "retention_until >= created_at + INTERVAL '1 hour' AND " \
      "retention_until <= created_at + INTERVAL '10 years'",
      name: "secure_evidence_attachments_retention_window"
    add_check_constraint :secure_evidence_attachments,
      "(scanned_at IS NULL OR scanned_at >= created_at) AND " \
      "(quarantined_at IS NULL OR " \
      "(scanned_at IS NOT NULL AND quarantined_at >= scanned_at)) AND " \
      "(purged_at IS NULL OR purged_at >= created_at)",
      name: "secure_evidence_attachments_timestamp_order"
    add_check_constraint :secure_evidence_attachments,
      "(state <> 'available' OR scanned_at IS NOT NULL) AND " \
      "(state <> 'quarantined' OR quarantined_at IS NOT NULL) AND " \
      "((state = 'purged') = (purged_at IS NOT NULL))",
      name: "secure_evidence_attachments_state_shape"
  end

  def create_events
    create_table :secure_evidence_attachment_events do |t|
      t.references :secure_evidence_attachment,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { name: "idx_secure_evidence_events_attachment" }
      t.references :actor,
        null: true,
        foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :event_type, null: false
      t.string :idempotency_key, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :secure_evidence_attachment_events,
      :idempotency_key,
      unique: true,
      name: "idx_secure_evidence_events_idempotency"
    add_index :secure_evidence_attachment_events,
      %i[secure_evidence_attachment_id occurred_at],
      name: "idx_secure_evidence_events_timeline"
    add_check_constraint :secure_evidence_attachment_events,
      "event_type IN (" \
      "'created', 'scan_clean', 'scan_infected', 'scan_error', 'downloaded', " \
      "'retention_extended', 'cleanup_scheduled', 'cleanup_failed', 'purged'" \
      ")",
      name: "secure_evidence_events_valid_type"
    add_check_constraint :secure_evidence_attachment_events,
      "idempotency_key ~ '^[A-Za-z0-9:._-]{8,180}$'",
      name: "secure_evidence_events_idempotency_format"
    add_check_constraint :secure_evidence_attachment_events,
      "jsonb_typeof(metadata) = 'object'",
      name: "secure_evidence_events_metadata_object"
  end

  def extend_uploads
    remove_check_constraint :forum_uploads,
      name: "forum_uploads_valid_kind",
      if_exists: true
    add_check_constraint :forum_uploads,
      "kind IN ('inline_image', 'post_attachment', 'secure_evidence_attachment')",
      name: "forum_uploads_valid_kind"
    add_reference :forum_uploads,
      :secure_evidence_attachment,
      null: true,
      foreign_key: { on_delete: :nullify },
      index: { unique: true, name: "idx_forum_uploads_secure_evidence_attachment" }
    add_check_constraint :forum_uploads,
      "secure_evidence_attachment_id IS NULL OR kind = 'secure_evidence_attachment'",
      name: "forum_uploads_secure_evidence_kind"
  end

  def prepare_uploads_for_rollback
    return unless column_exists?(:forum_uploads, :secure_evidence_attachment_id)

    execute <<~SQL.squish
      UPDATE forum_uploads
      SET kind = 'post_attachment',
          status = CASE WHEN status = 'cleaned' THEN status ELSE 'cleanup_pending' END,
          expires_at = CASE WHEN status = 'cleaned' THEN expires_at ELSE CURRENT_TIMESTAMP END,
          cleanup_started_at = NULL,
          secure_evidence_attachment_id = NULL,
          updated_at = CURRENT_TIMESTAMP
      WHERE kind = 'secure_evidence_attachment'
    SQL
  end

  def remove_upload_extension
    remove_check_constraint :forum_uploads,
      name: "forum_uploads_secure_evidence_kind",
      if_exists: true
    remove_index :forum_uploads,
      name: "idx_forum_uploads_secure_evidence_attachment",
      if_exists: true
    remove_reference :forum_uploads,
      :secure_evidence_attachment,
      foreign_key: true,
      index: false,
      if_exists: true
  end

  def restore_upload_kind_constraint
    remove_check_constraint :forum_uploads,
      name: "forum_uploads_valid_kind",
      if_exists: true
    add_check_constraint :forum_uploads,
      "kind IN ('inline_image', 'post_attachment')",
      name: "forum_uploads_valid_kind"
  end

  def create_event_immutability
    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{EVENT_FUNCTION}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'secure_evidence_attachment_events is append-only';
      END;
      $$;

      CREATE TRIGGER #{EVENT_TRIGGER}
      BEFORE UPDATE OR DELETE ON secure_evidence_attachment_events
      FOR EACH ROW
      EXECUTE FUNCTION #{EVENT_FUNCTION}();
    SQL
  end

  def drop_event_immutability
    if table_exists?(:secure_evidence_attachment_events)
      execute "DROP TRIGGER IF EXISTS #{EVENT_TRIGGER} ON secure_evidence_attachment_events"
    end
    execute "DROP FUNCTION IF EXISTS #{EVENT_FUNCTION}()"
  end

  def create_attachment_delete_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{ATTACHMENT_FUNCTION}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'secure_evidence_attachments metadata cannot be deleted';
      END;
      $$;

      CREATE TRIGGER #{ATTACHMENT_TRIGGER}
      BEFORE DELETE ON secure_evidence_attachments
      FOR EACH ROW
      EXECUTE FUNCTION #{ATTACHMENT_FUNCTION}();
    SQL
  end

  def drop_attachment_delete_guard
    if table_exists?(:secure_evidence_attachments)
      execute "DROP TRIGGER IF EXISTS #{ATTACHMENT_TRIGGER} ON secure_evidence_attachments"
    end
    execute "DROP FUNCTION IF EXISTS #{ATTACHMENT_FUNCTION}()"
  end

  def create_attachment_update_guard
    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{ATTACHMENT_UPDATE_FUNCTION}()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.public_id IS DISTINCT FROM OLD.public_id
           OR NEW.uploader_id IS DISTINCT FROM OLD.uploader_id
           OR NEW.uploader_public_id_snapshot IS DISTINCT FROM OLD.uploader_public_id_snapshot
           OR NEW.subject_key IS DISTINCT FROM OLD.subject_key
           OR NEW.subject_id IS DISTINCT FROM OLD.subject_id
           OR NEW.subject_public_id IS DISTINCT FROM OLD.subject_public_id
           OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
           OR NEW.request_fingerprint IS DISTINCT FROM OLD.request_fingerprint
           OR NEW.filename IS DISTINCT FROM OLD.filename
           OR NEW.content_type IS DISTINCT FROM OLD.content_type
           OR NEW.byte_size IS DISTINCT FROM OLD.byte_size
           OR NEW.sha256 IS DISTINCT FROM OLD.sha256
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'secure evidence attachment identity is immutable';
        END IF;

        IF NEW.retention_until < OLD.retention_until THEN
          RAISE EXCEPTION 'secure evidence retention cannot be shortened';
        END IF;

        IF NOT (
          (OLD.state = 'pending' AND NEW.state IN ('pending', 'available', 'quarantined', 'purge_pending'))
          OR (OLD.state = 'available' AND NEW.state IN ('available', 'purge_pending'))
          OR (OLD.state = 'quarantined' AND NEW.state IN ('quarantined', 'purge_pending'))
          OR (OLD.state = 'purge_pending' AND NEW.state IN ('purge_pending', 'purged'))
          OR (OLD.state = 'purged' AND NEW.state = 'purged')
        ) THEN
          RAISE EXCEPTION 'secure evidence attachment state transition is invalid';
        END IF;

        IF OLD.state = 'purged' AND NEW IS DISTINCT FROM OLD THEN
          RAISE EXCEPTION 'purged secure evidence metadata is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER #{ATTACHMENT_UPDATE_TRIGGER}
      BEFORE UPDATE ON secure_evidence_attachments
      FOR EACH ROW
      EXECUTE FUNCTION #{ATTACHMENT_UPDATE_FUNCTION}();
    SQL
  end

  def drop_attachment_update_guard
    if table_exists?(:secure_evidence_attachments)
      execute "DROP TRIGGER IF EXISTS #{ATTACHMENT_UPDATE_TRIGGER} ON secure_evidence_attachments"
    end
    execute "DROP FUNCTION IF EXISTS #{ATTACHMENT_UPDATE_FUNCTION}()"
  end
end
