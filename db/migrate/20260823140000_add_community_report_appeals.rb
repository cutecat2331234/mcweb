# frozen_string_literal: true

class AddCommunityReportAppeals < ActiveRecord::Migration[8.1]
  ACTIVE_APPEAL_STATUSES = %w[draft submitted under_review].freeze
  TERMINAL_APPEAL_STATUSES = %w[upheld overturned cancelled].freeze
  APPEAL_STATUSES = (ACTIVE_APPEAL_STATUSES + TERMINAL_APPEAL_STATUSES).freeze
  APPELLANT_ROLES = %w[reporter affected_subject].freeze
  DIGEST_CHECK = "~ '^[0-9a-f]{64}$'"

  def up
    extend_reports
    create_appeals
    create_appeal_events
    create_evidence_links
    create_appeal_outcome_deliveries
    create_subject_action_deliveries
    create_immutability_guards
    replace_report_outcome_delivery_contract(use_public_ids: true)
    migrate_report_notification_references(use_public_ids: true)
  end

  def down
    migrate_report_notification_references(use_public_ids: false)
    replace_report_outcome_delivery_contract(use_public_ids: false)
    drop_immutability_guards
    drop_table :forum_report_appeal_outcome_deliveries, if_exists: true
    drop_table :forum_report_subject_action_deliveries, if_exists: true
    remove_new_notification_types
    drop_table :forum_report_appeal_attachments, if_exists: true
    drop_table :forum_report_attachments, if_exists: true
    drop_table :forum_report_appeal_events, if_exists: true
    drop_table :forum_report_appeals, if_exists: true
    remove_foreign_key :forum_reports, column: :affected_user_id, if_exists: true
    remove_index :forum_reports, name: "idx_forum_reports_affected_user", if_exists: true
    remove_index :forum_reports, name: "idx_forum_reports_public_id", if_exists: true
    remove_column :forum_reports, :affected_user_id, if_exists: true
    remove_column :forum_reports, :public_id, if_exists: true
  end

  private

  def extend_reports
    add_column :forum_reports, :public_id, :string, limit: 64
    add_column :forum_reports, :affected_user_id, :bigint
    execute <<~SQL.squish
      UPDATE forum_reports
      SET public_id = 'rpt_' || substr(md5(id::text || ':' || created_at::text || ':' || random()::text), 1, 24)
      WHERE public_id IS NULL
    SQL
    change_column_null :forum_reports, :public_id, false
    add_index :forum_reports,
      :public_id,
      unique: true,
      name: "idx_forum_reports_public_id"
    add_index :forum_reports,
      :affected_user_id,
      name: "idx_forum_reports_affected_user"
    add_check_constraint :forum_reports,
      "char_length(public_id) BETWEEN 12 AND 64",
      name: "forum_reports_public_id_length"
    add_check_constraint :forum_reports,
      "affected_user_id IS NULL OR status = 'actioned'",
      name: "forum_reports_affected_user_shape"
    add_foreign_key :forum_reports,
      :users,
      column: :affected_user_id,
      on_delete: :restrict,
      validate: false
    backfill_affected_users
    validate_foreign_key :forum_reports, :users, column: :affected_user_id
  end

  def backfill_affected_users
    mappings = {
      "Community::Topic" => [ "forum_topics", "id", "user_id" ],
      "Community::Post" => [ "forum_posts", "id", "user_id" ],
      "Community::Message" => [ "forum_messages", "id", "user_id" ],
      "Community::ProfilePost" => [ "forum_profile_posts", "id", "user_id" ],
      "Community::ProfilePostComment" => [ "forum_profile_post_comments", "id", "user_id" ],
      "Commerce::Review" => [ "store_reviews", "id", "user_id" ],
      "User" => [ "users", "id", "id" ]
    }
    mappings.each do |type, (table, primary_key, user_column)|
      execute <<~SQL.squish
        UPDATE forum_reports reports
        SET affected_user_id = targets.#{user_column}
        FROM #{table} targets
        WHERE reports.reportable_type = #{connection.quote(type)}
          AND reports.reportable_id = targets.#{primary_key}
          AND reports.status = 'actioned'
          AND reports.affected_user_id IS NULL
      SQL
    end
  end

  def create_appeals
    create_table :forum_report_appeals do |t|
      t.string :public_id, null: false, limit: 64
      t.references :forum_report,
        null: false,
        foreign_key: { to_table: :forum_reports, on_delete: :restrict }
      t.references :appellant,
        null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :appellant_role, null: false
      t.text :reason
      t.string :status, null: false, default: "draft"
      t.string :public_outcome_code
      t.references :reviewer,
        null: true,
        foreign_key: { to_table: :users, on_delete: :restrict }
      t.text :internal_note
      t.datetime :state_changed_at, null: false
      t.datetime :expires_at
      t.datetime :submitted_at
      t.datetime :review_started_at
      t.datetime :decided_at
      t.datetime :cancelled_at
      t.string :draft_idempotency_key_digest, null: false, limit: 64
      t.string :draft_request_fingerprint, null: false, limit: 64
      t.string :submit_idempotency_key_digest, limit: 64
      t.string :submit_request_fingerprint, limit: 64
      t.string :cancel_idempotency_key_digest, limit: 64
      t.string :cancel_request_fingerprint, limit: 64
      t.string :decision_idempotency_key_digest, limit: 64
      t.string :decision_request_fingerprint, limit: 64
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :forum_report_appeals,
      :public_id,
      unique: true,
      name: "idx_forum_report_appeals_public_id"
    add_index :forum_report_appeals,
      %i[appellant_id draft_idempotency_key_digest],
      unique: true,
      name: "idx_forum_report_appeals_draft_idempotency"
    add_index :forum_report_appeals,
      %i[forum_report_id appellant_id appellant_role],
      unique: true,
      where: "status IN ('draft', 'submitted', 'under_review')",
      name: "idx_forum_report_appeals_one_active"
    add_index :forum_report_appeals,
      %i[status state_changed_at id],
      name: "idx_forum_report_appeals_queue"
    add_index :forum_report_appeals,
      %i[status expires_at],
      where: "status = 'draft'",
      name: "idx_forum_report_appeals_draft_expiry"
    add_check_constraint :forum_report_appeals,
      "appellant_role IN (#{quoted(APPELLANT_ROLES)})",
      name: "forum_report_appeals_role"
    add_check_constraint :forum_report_appeals,
      "status IN (#{quoted(APPEAL_STATUSES)})",
      name: "forum_report_appeals_status"
    add_check_constraint :forum_report_appeals,
      "char_length(public_id) BETWEEN 12 AND 64",
      name: "forum_report_appeals_public_id_length"
    add_check_constraint :forum_report_appeals,
      "reason IS NULL OR char_length(btrim(reason)) BETWEEN 1 AND 5000",
      name: "forum_report_appeals_reason_length"
    add_check_constraint :forum_report_appeals,
      appeal_shape_check,
      name: "forum_report_appeals_state_shape"
    add_check_constraint :forum_report_appeals,
      digest_columns_check,
      name: "forum_report_appeals_digest_shape"
  end

  def create_appeal_events
    create_table :forum_report_appeal_events do |t|
      t.references :forum_report_appeal,
        null: false,
        foreign_key: { on_delete: :restrict },
        index: { name: "idx_forum_report_appeal_events_appeal" }
      t.references :actor,
        null: true,
        foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :event_type, null: false
      t.string :from_status
      t.string :to_status, null: false
      t.string :public_outcome_code
      t.string :idempotency_key_digest, null: false, limit: 64
      t.string :request_fingerprint, null: false, limit: 64
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end
    add_index :forum_report_appeal_events,
      %i[forum_report_appeal_id occurred_at id],
      name: "idx_forum_report_appeal_events_timeline"
    add_index :forum_report_appeal_events,
      %i[forum_report_appeal_id event_type idempotency_key_digest],
      unique: true,
      name: "idx_forum_report_appeal_events_idempotency"
    add_check_constraint :forum_report_appeal_events,
      "event_type IN ('drafted', 'submitted', 'review_started', 'upheld', 'overturned', 'cancelled')",
      name: "forum_report_appeal_events_type"
    add_check_constraint :forum_report_appeal_events,
      "(from_status IS NULL OR from_status IN (#{quoted(APPEAL_STATUSES)})) AND " \
        "to_status IN (#{quoted(APPEAL_STATUSES)})",
      name: "forum_report_appeal_events_status"
    add_check_constraint :forum_report_appeal_events,
      "idempotency_key_digest #{DIGEST_CHECK} AND request_fingerprint #{DIGEST_CHECK}",
      name: "forum_report_appeal_events_digests"
  end

  def create_evidence_links
    create_table :forum_report_attachments do |t|
      t.references :forum_report,
        null: false,
        foreign_key: { to_table: :forum_reports, on_delete: :restrict }
      t.references :secure_evidence_attachment,
        null: false,
        foreign_key: { on_delete: :restrict },
        index: { unique: true, name: "idx_forum_report_attachments_evidence" }
      t.references :sealed_by,
        null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }
      t.datetime :created_at, null: false
    end
    add_index :forum_report_attachments,
      %i[forum_report_id created_at],
      name: "idx_forum_report_attachments_timeline"

    create_table :forum_report_appeal_attachments do |t|
      t.references :forum_report_appeal,
        null: false,
        foreign_key: { on_delete: :restrict }
      t.references :secure_evidence_attachment,
        null: false,
        foreign_key: { on_delete: :restrict },
        index: { unique: true, name: "idx_forum_report_appeal_attachments_evidence" }
      t.references :sealed_by,
        null: false,
        foreign_key: { to_table: :users, on_delete: :restrict }
      t.string :audience, null: false
      t.datetime :created_at, null: false
    end
    add_index :forum_report_appeal_attachments,
      %i[forum_report_appeal_id created_at],
      name: "idx_forum_report_appeal_attachments_timeline"
    add_check_constraint :forum_report_appeal_attachments,
      "audience IN ('appellant', 'reviewers')",
      name: "forum_report_appeal_attachments_audience"
  end

  def create_appeal_outcome_deliveries
    create_table :forum_report_appeal_outcome_deliveries do |t|
      t.references :forum_report_appeal,
        null: false,
        foreign_key: { on_delete: :restrict },
        index: { unique: true, name: "idx_forum_report_appeal_deliveries_appeal" }
      t.references :notification,
        null: true,
        foreign_key: { on_delete: :nullify },
        index: { unique: true, name: "idx_forum_report_appeal_deliveries_notification" }
      t.string :public_outcome_code, null: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :forum_report_appeal_outcome_deliveries,
      "public_outcome_code IN ('upheld', 'overturned')",
      name: "forum_report_appeal_deliveries_outcome"
  end

  def create_subject_action_deliveries
    create_table :forum_report_subject_action_deliveries do |t|
      t.references :forum_report,
        null: false,
        foreign_key: { to_table: :forum_reports, on_delete: :restrict },
        index: { unique: true, name: "idx_forum_report_subject_deliveries_report" }
      t.references :notification,
        null: true,
        foreign_key: { on_delete: :nullify },
        index: { unique: true, name: "idx_forum_report_subject_deliveries_notification" }
      t.datetime :created_at, null: false
    end
  end

  def create_immutability_guards
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_report_appeals_guard_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.public_id IS DISTINCT FROM OLD.public_id
           OR NEW.forum_report_id IS DISTINCT FROM OLD.forum_report_id
           OR NEW.appellant_id IS DISTINCT FROM OLD.appellant_id
           OR NEW.appellant_role IS DISTINCT FROM OLD.appellant_role
           OR NEW.draft_idempotency_key_digest IS DISTINCT FROM OLD.draft_idempotency_key_digest
           OR NEW.draft_request_fingerprint IS DISTINCT FROM OLD.draft_request_fingerprint
           OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
          RAISE EXCEPTION 'forum report appeal identity is immutable';
        END IF;

        IF (NEW.submit_idempotency_key_digest IS DISTINCT FROM OLD.submit_idempotency_key_digest
             OR NEW.submit_request_fingerprint IS DISTINCT FROM OLD.submit_request_fingerprint)
           AND NOT (
             OLD.submit_idempotency_key_digest IS NULL
             AND OLD.submit_request_fingerprint IS NULL
             AND NEW.submit_idempotency_key_digest IS NOT NULL
             AND NEW.submit_request_fingerprint IS NOT NULL
             AND OLD.status = 'draft'
             AND NEW.status = 'submitted'
           ) THEN
          RAISE EXCEPTION 'forum report appeal submit identity is immutable';
        END IF;

        IF (NEW.cancel_idempotency_key_digest IS DISTINCT FROM OLD.cancel_idempotency_key_digest
             OR NEW.cancel_request_fingerprint IS DISTINCT FROM OLD.cancel_request_fingerprint)
           AND NOT (
             OLD.cancel_idempotency_key_digest IS NULL
             AND OLD.cancel_request_fingerprint IS NULL
             AND NEW.cancel_idempotency_key_digest IS NOT NULL
             AND NEW.cancel_request_fingerprint IS NOT NULL
             AND OLD.status IN ('draft', 'submitted')
             AND NEW.status = 'cancelled'
           ) THEN
          RAISE EXCEPTION 'forum report appeal cancel identity is immutable';
        END IF;

        IF (NEW.decision_idempotency_key_digest IS DISTINCT FROM OLD.decision_idempotency_key_digest
             OR NEW.decision_request_fingerprint IS DISTINCT FROM OLD.decision_request_fingerprint)
           AND NOT (
             OLD.decision_idempotency_key_digest IS NULL
             AND OLD.decision_request_fingerprint IS NULL
             AND NEW.decision_idempotency_key_digest IS NOT NULL
             AND NEW.decision_request_fingerprint IS NOT NULL
             AND OLD.status = 'under_review'
             AND NEW.status IN ('upheld', 'overturned')
           ) THEN
          RAISE EXCEPTION 'forum report appeal decision identity is immutable';
        END IF;

        IF OLD.status IN ('submitted', 'under_review', 'upheld', 'overturned', 'cancelled')
           AND NEW.reason IS DISTINCT FROM OLD.reason THEN
          RAISE EXCEPTION 'submitted forum report appeal reason is immutable';
        END IF;

        IF NOT (
          (OLD.status = 'draft' AND NEW.status IN ('draft', 'submitted', 'cancelled'))
          OR (OLD.status = 'submitted' AND NEW.status IN ('submitted', 'under_review', 'cancelled'))
          OR (OLD.status = 'under_review' AND NEW.status IN ('under_review', 'upheld', 'overturned'))
          OR (OLD.status IN ('upheld', 'overturned', 'cancelled') AND NEW.status = OLD.status)
        ) THEN
          RAISE EXCEPTION 'forum report appeal state transition is invalid';
        END IF;

        IF OLD.status IN ('upheld', 'overturned', 'cancelled') AND NEW IS DISTINCT FROM OLD THEN
          RAISE EXCEPTION 'terminal forum report appeal is immutable';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_appeals_guard_change
      BEFORE UPDATE ON forum_report_appeals
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeals_guard_change();

      CREATE OR REPLACE FUNCTION forum_report_appeals_reject_delete()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum report appeals cannot be deleted';
      END;
      $$;

      CREATE TRIGGER forum_report_appeals_reject_delete
      BEFORE DELETE ON forum_report_appeals
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeals_reject_delete();

      CREATE OR REPLACE FUNCTION forum_reports_guard_affected_user()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF NEW.public_id IS DISTINCT FROM OLD.public_id THEN
          RAISE EXCEPTION 'forum report public id is immutable';
        END IF;

        IF NEW.affected_user_id IS DISTINCT FROM OLD.affected_user_id
           AND NOT (
             OLD.affected_user_id IS NULL
             AND OLD.status = 'pending'
             AND NEW.status = 'actioned'
             AND NEW.affected_user_id IS NOT NULL
           ) THEN
          RAISE EXCEPTION 'forum report affected user is immutable';
        END IF;

        IF NEW.affected_user_id IS NOT NULL AND NEW.status IS DISTINCT FROM 'actioned' THEN
          RAISE EXCEPTION 'forum report affected user does not match outcome';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_reports_affected_user_guard
      BEFORE UPDATE ON forum_reports
      FOR EACH ROW
      EXECUTE FUNCTION forum_reports_guard_affected_user();

      CREATE OR REPLACE FUNCTION forum_report_appeal_events_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum report appeal events are append-only';
      END;
      $$;

      CREATE TRIGGER forum_report_appeal_events_immutable
      BEFORE UPDATE OR DELETE ON forum_report_appeal_events
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeal_events_reject_change();

      CREATE OR REPLACE FUNCTION forum_report_case_attachments_guard_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum report evidence links are immutable';
      END;
      $$;

      CREATE TRIGGER forum_report_attachments_immutable
      BEFORE UPDATE OR DELETE ON forum_report_attachments
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_case_attachments_guard_change();

      CREATE TRIGGER forum_report_appeal_attachments_immutable
      BEFORE UPDATE OR DELETE ON forum_report_appeal_attachments
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_case_attachments_guard_change();

      CREATE OR REPLACE FUNCTION forum_report_attachments_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        attachment_subject_key text;
        attachment_subject_id bigint;
        attachment_subject_public_id text;
        attachment_uploader_id bigint;
        attachment_state text;
        upload_scan_status text;
        report_public_id text;
        report_owner_id bigint;
        report_status text;
      BEGIN
        SELECT public_id, reporter_id, status
        INTO report_public_id, report_owner_id, report_status
        FROM forum_reports
        WHERE id = NEW.forum_report_id
        FOR UPDATE;

        SELECT evidence.subject_key,
               evidence.subject_id,
               evidence.subject_public_id,
               evidence.uploader_id,
               evidence.state,
               uploads.scan_status
        INTO attachment_subject_key,
             attachment_subject_id,
             attachment_subject_public_id,
             attachment_uploader_id,
             attachment_state,
             upload_scan_status
        FROM secure_evidence_attachments evidence
        INNER JOIN forum_uploads uploads
          ON uploads.secure_evidence_attachment_id = evidence.id
        WHERE evidence.id = NEW.secure_evidence_attachment_id
        FOR UPDATE OF evidence, uploads;

        IF attachment_subject_key IS DISTINCT FROM 'community.report'
           OR attachment_subject_id IS DISTINCT FROM NEW.forum_report_id
           OR attachment_subject_public_id IS DISTINCT FROM report_public_id
           OR attachment_uploader_id IS DISTINCT FROM NEW.sealed_by_id
           OR NEW.sealed_by_id IS DISTINCT FROM report_owner_id
           OR report_status IS DISTINCT FROM 'pending'
           OR attachment_state IS DISTINCT FROM 'available'
           OR upload_scan_status IS DISTINCT FROM 'clean'
           OR EXISTS (
             SELECT 1
             FROM forum_report_appeal_attachments
             WHERE secure_evidence_attachment_id = NEW.secure_evidence_attachment_id
           ) THEN
          RAISE EXCEPTION 'forum report evidence is not clean or does not belong to this subject';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_attachments_insert_contract
      BEFORE INSERT ON forum_report_attachments
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_attachments_validate_insert();

      CREATE OR REPLACE FUNCTION forum_report_appeal_attachments_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        attachment_subject_key text;
        attachment_subject_id bigint;
        attachment_subject_public_id text;
        attachment_uploader_id bigint;
        attachment_state text;
        upload_scan_status text;
        appeal_appellant_id bigint;
        appeal_public_id text;
        appeal_status text;
      BEGIN
        SELECT appellant_id, public_id, status
        INTO appeal_appellant_id, appeal_public_id, appeal_status
        FROM forum_report_appeals
        WHERE id = NEW.forum_report_appeal_id
        FOR UPDATE;

        SELECT evidence.subject_key,
               evidence.subject_id,
               evidence.subject_public_id,
               evidence.uploader_id,
               evidence.state,
               uploads.scan_status
        INTO attachment_subject_key,
             attachment_subject_id,
             attachment_subject_public_id,
             attachment_uploader_id,
             attachment_state,
             upload_scan_status
        FROM secure_evidence_attachments evidence
        INNER JOIN forum_uploads uploads
          ON uploads.secure_evidence_attachment_id = evidence.id
        WHERE evidence.id = NEW.secure_evidence_attachment_id
        FOR UPDATE OF evidence, uploads;

        IF attachment_subject_key IS DISTINCT FROM 'community.report_appeal'
           OR attachment_subject_id IS DISTINCT FROM NEW.forum_report_appeal_id
           OR attachment_subject_public_id IS DISTINCT FROM appeal_public_id
           OR attachment_uploader_id IS DISTINCT FROM NEW.sealed_by_id
           OR attachment_state IS DISTINCT FROM 'available'
           OR upload_scan_status IS DISTINCT FROM 'clean'
           OR NOT (
             (NEW.audience = 'appellant'
               AND NEW.sealed_by_id = appeal_appellant_id
               AND appeal_status = 'submitted')
             OR (NEW.audience = 'reviewers'
               AND NEW.sealed_by_id <> appeal_appellant_id
               AND appeal_status IN ('submitted', 'under_review'))
           )
           OR EXISTS (
             SELECT 1
             FROM forum_report_attachments
             WHERE secure_evidence_attachment_id = NEW.secure_evidence_attachment_id
           ) THEN
          RAISE EXCEPTION 'forum report appeal evidence is not clean or does not belong to this subject';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_appeal_attachments_insert_contract
      BEFORE INSERT ON forum_report_appeal_attachments
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeal_attachments_validate_insert();

      CREATE OR REPLACE FUNCTION forum_report_appeal_deliveries_guard_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'UPDATE'
           AND OLD.notification_id IS NOT NULL
           AND NEW.notification_id IS NULL
           AND NEW.forum_report_appeal_id = OLD.forum_report_appeal_id
           AND NEW.public_outcome_code = OLD.public_outcome_code
           AND NEW.created_at = OLD.created_at THEN
          RETURN NEW;
        END IF;

        RAISE EXCEPTION 'forum report appeal delivery receipts are immutable';
      END;
      $$;

      CREATE TRIGGER forum_report_appeal_deliveries_immutable
      BEFORE UPDATE OR DELETE ON forum_report_appeal_outcome_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeal_deliveries_guard_change();

      CREATE OR REPLACE FUNCTION forum_report_appeal_deliveries_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        appeal_status text;
        appeal_outcome text;
        appeal_public_id text;
        appellant_id bigint;
        notification_owner_id bigint;
        notification_kind text;
        notification_metadata jsonb;
      BEGIN
        SELECT appeals.status,
               appeals.public_outcome_code,
               appeals.public_id,
               appeals.appellant_id,
               notifications.user_id,
               notifications.notification_type,
               notifications.metadata
        INTO appeal_status,
             appeal_outcome,
             appeal_public_id,
             appellant_id,
             notification_owner_id,
             notification_kind,
             notification_metadata
        FROM forum_report_appeals appeals
        INNER JOIN notifications ON notifications.id = NEW.notification_id
        WHERE appeals.id = NEW.forum_report_appeal_id
        FOR UPDATE OF appeals;

        IF NEW.notification_id IS NULL
           OR appeal_status NOT IN ('upheld', 'overturned')
           OR appeal_outcome IS DISTINCT FROM appeal_status
           OR NEW.public_outcome_code IS DISTINCT FROM appeal_outcome
           OR notification_owner_id IS DISTINCT FROM appellant_id
           OR notification_kind IS DISTINCT FROM 'forum.report_appeal_outcome'
           OR notification_metadata ->> 'appeal_public_id' IS DISTINCT FROM appeal_public_id
           OR notification_metadata ->> 'public_outcome_code' IS DISTINCT FROM appeal_outcome
           OR notification_metadata ->> 'path' IS DISTINCT FROM '/app/forum/report-appeals/' || appeal_public_id THEN
          RAISE EXCEPTION 'forum report appeal outcome delivery contract is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_appeal_deliveries_insert_contract
      BEFORE INSERT ON forum_report_appeal_outcome_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_appeal_deliveries_validate_insert();

      CREATE OR REPLACE FUNCTION forum_report_subject_deliveries_guard_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'UPDATE'
           AND OLD.notification_id IS NOT NULL
           AND NEW.notification_id IS NULL
           AND NEW.forum_report_id = OLD.forum_report_id
           AND NEW.created_at = OLD.created_at THEN
          RETURN NEW;
        END IF;

        RAISE EXCEPTION 'forum report subject action delivery receipts are immutable';
      END;
      $$;

      CREATE TRIGGER forum_report_subject_deliveries_immutable
      BEFORE UPDATE OR DELETE ON forum_report_subject_action_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_subject_deliveries_guard_change();

      CREATE OR REPLACE FUNCTION forum_report_subject_deliveries_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        report_status text;
        report_public_id text;
        report_subject_id bigint;
        notification_owner_id bigint;
        notification_kind text;
        notification_metadata jsonb;
      BEGIN
        SELECT reports.status,
               reports.public_id,
               reports.affected_user_id,
               notifications.user_id,
               notifications.notification_type,
               notifications.metadata
        INTO report_status,
             report_public_id,
             report_subject_id,
             notification_owner_id,
             notification_kind,
             notification_metadata
        FROM forum_reports reports
        INNER JOIN notifications ON notifications.id = NEW.notification_id
        WHERE reports.id = NEW.forum_report_id
        FOR UPDATE OF reports;

        IF NEW.notification_id IS NULL
           OR report_status IS DISTINCT FROM 'actioned'
           OR report_subject_id IS NULL
           OR notification_owner_id IS DISTINCT FROM report_subject_id
           OR notification_kind IS DISTINCT FROM 'forum.report_subject_action'
           OR notification_metadata ->> 'report_public_id' IS DISTINCT FROM report_public_id
           OR notification_metadata ->> 'path' IS DISTINCT FROM '/app/forum/report-appeals' THEN
          RAISE EXCEPTION 'forum report subject action delivery contract is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_subject_deliveries_insert_contract
      BEFORE INSERT ON forum_report_subject_action_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_subject_deliveries_validate_insert();
    SQL
  end

  def drop_immutability_guards
    drop_trigger(:forum_report_appeal_outcome_deliveries, "forum_report_appeal_deliveries_insert_contract")
    drop_trigger(:forum_report_appeal_outcome_deliveries, "forum_report_appeal_deliveries_immutable")
    drop_trigger(:forum_report_subject_action_deliveries, "forum_report_subject_deliveries_insert_contract")
    drop_trigger(:forum_report_subject_action_deliveries, "forum_report_subject_deliveries_immutable")
    drop_trigger(:forum_report_appeal_attachments, "forum_report_appeal_attachments_insert_contract")
    drop_trigger(:forum_report_attachments, "forum_report_attachments_insert_contract")
    drop_trigger(:forum_report_appeal_attachments, "forum_report_appeal_attachments_immutable")
    drop_trigger(:forum_report_attachments, "forum_report_attachments_immutable")
    drop_trigger(:forum_report_appeal_events, "forum_report_appeal_events_immutable")
    drop_trigger(:forum_reports, "forum_reports_affected_user_guard")
    drop_trigger(:forum_report_appeals, "forum_report_appeals_reject_delete")
    drop_trigger(:forum_report_appeals, "forum_report_appeals_guard_change")
    execute "DROP FUNCTION IF EXISTS forum_report_appeal_deliveries_guard_change()"
    execute "DROP FUNCTION IF EXISTS forum_report_appeal_deliveries_validate_insert()"
    execute "DROP FUNCTION IF EXISTS forum_report_subject_deliveries_validate_insert()"
    execute "DROP FUNCTION IF EXISTS forum_report_subject_deliveries_guard_change()"
    execute "DROP FUNCTION IF EXISTS forum_report_appeal_attachments_validate_insert()"
    execute "DROP FUNCTION IF EXISTS forum_report_attachments_validate_insert()"
    execute "DROP FUNCTION IF EXISTS forum_report_case_attachments_guard_change()"
    execute "DROP FUNCTION IF EXISTS forum_report_appeal_events_reject_change()"
    execute "DROP FUNCTION IF EXISTS forum_reports_guard_affected_user()"
    execute "DROP FUNCTION IF EXISTS forum_report_appeals_reject_delete()"
    execute "DROP FUNCTION IF EXISTS forum_report_appeals_guard_change()"
  end

  def migrate_report_notification_references(use_public_ids:)
    if use_public_ids
      execute <<~SQL.squish
        UPDATE notifications notifications
        SET metadata = (COALESCE(notifications.metadata, '{}'::jsonb) - 'report_id') ||
          jsonb_build_object(
            'report_public_id', reports.public_id,
            'path', '/app/forum/reports/' || reports.public_id
          )
        FROM forum_report_outcome_deliveries deliveries
        INNER JOIN forum_reports reports ON reports.id = deliveries.forum_report_id
        WHERE notifications.id = deliveries.notification_id
      SQL
    else
      execute <<~SQL.squish
        UPDATE notifications notifications
        SET metadata = (COALESCE(notifications.metadata, '{}'::jsonb) - 'report_public_id') ||
          jsonb_build_object(
            'report_id', reports.id,
            'path', '/app/forum/reports/' || reports.id
          )
        FROM forum_report_outcome_deliveries deliveries
        INNER JOIN forum_reports reports ON reports.id = deliveries.forum_report_id
        WHERE notifications.id = deliveries.notification_id
      SQL
    end
  end

  def remove_new_notification_types
    execute <<~SQL.squish
      DELETE FROM notifications
      WHERE notification_type IN ('forum.report_appeal_outcome', 'forum.report_subject_action')
    SQL
  end

  def replace_report_outcome_delivery_contract(use_public_ids:)
    metadata_id_key = use_public_ids ? "report_public_id" : "report_id"
    metadata_id_value = use_public_ids ? "reports.public_id" : "reports.id::text"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_report_outcome_deliveries_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        report_status text;
        report_outcome text;
        report_owner_id bigint;
        report_reference text;
        notification_owner_id bigint;
        notification_kind text;
        notification_metadata jsonb;
      BEGIN
        SELECT reports.status,
               reports.public_outcome_code,
               reports.reporter_id,
               #{metadata_id_value},
               notifications.user_id,
               notifications.notification_type,
               notifications.metadata
        INTO report_status,
             report_outcome,
             report_owner_id,
             report_reference,
             notification_owner_id,
             notification_kind,
             notification_metadata
        FROM forum_reports reports
        INNER JOIN notifications ON notifications.id = NEW.notification_id
        WHERE reports.id = NEW.forum_report_id
        FOR UPDATE OF reports;

        IF NEW.notification_id IS NULL
           OR report_status IS NULL
           OR report_status NOT IN ('reviewed', 'dismissed', 'actioned')
           OR report_outcome IS NULL
           OR NEW.public_outcome_code IS DISTINCT FROM report_outcome
           OR notification_owner_id IS DISTINCT FROM report_owner_id
           OR notification_kind IS DISTINCT FROM 'forum.report_outcome'
           OR notification_metadata ->> '#{metadata_id_key}' IS DISTINCT FROM report_reference
           OR notification_metadata ->> 'public_outcome_code' IS DISTINCT FROM NEW.public_outcome_code
           OR notification_metadata ->> 'path' IS DISTINCT FROM '/app/forum/reports/' || report_reference THEN
          RAISE EXCEPTION 'forum report outcome delivery contract is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;
    SQL
  end

  def appeal_shape_check
    <<~SQL.squish
      (status = 'draft' AND reason IS NULL AND public_outcome_code IS NULL
        AND reviewer_id IS NULL AND internal_note IS NULL AND expires_at IS NOT NULL
        AND submitted_at IS NULL AND review_started_at IS NULL AND decided_at IS NULL
        AND cancelled_at IS NULL)
      OR
      (status = 'submitted' AND reason IS NOT NULL AND public_outcome_code IS NULL
        AND reviewer_id IS NULL AND internal_note IS NULL AND expires_at IS NULL
        AND submitted_at IS NOT NULL AND review_started_at IS NULL AND decided_at IS NULL
        AND cancelled_at IS NULL)
      OR
      (status = 'under_review' AND reason IS NOT NULL AND public_outcome_code IS NULL
        AND reviewer_id IS NOT NULL AND expires_at IS NULL
        AND submitted_at IS NOT NULL AND review_started_at IS NOT NULL AND decided_at IS NULL
        AND cancelled_at IS NULL)
      OR
      (status IN ('upheld', 'overturned') AND reason IS NOT NULL
        AND public_outcome_code = status AND reviewer_id IS NOT NULL AND expires_at IS NULL
        AND submitted_at IS NOT NULL AND review_started_at IS NOT NULL AND decided_at IS NOT NULL
        AND cancelled_at IS NULL)
      OR
      (status = 'cancelled' AND public_outcome_code = 'cancelled' AND expires_at IS NULL
        AND reviewer_id IS NULL AND internal_note IS NULL AND review_started_at IS NULL
        AND decided_at IS NULL AND cancelled_at IS NOT NULL)
    SQL
  end

  def digest_columns_check
    required = %w[draft_idempotency_key_digest draft_request_fingerprint]
      .map { |column| "#{column} #{DIGEST_CHECK}" }
    optional = %w[
      submit_idempotency_key_digest submit_request_fingerprint
      cancel_idempotency_key_digest cancel_request_fingerprint
      decision_idempotency_key_digest decision_request_fingerprint
    ].map { |column| "(#{column} IS NULL OR #{column} #{DIGEST_CHECK})" }
    pairs = [
      "((submit_idempotency_key_digest IS NULL) = (submit_request_fingerprint IS NULL))",
      "((cancel_idempotency_key_digest IS NULL) = (cancel_request_fingerprint IS NULL))",
      "((decision_idempotency_key_digest IS NULL) = (decision_request_fingerprint IS NULL))"
    ]
    (required + optional + pairs).join(" AND ")
  end

  def quoted(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end

  def drop_trigger(table, name)
    execute "DROP TRIGGER IF EXISTS #{name} ON #{table}" if table_exists?(table)
  end
end
