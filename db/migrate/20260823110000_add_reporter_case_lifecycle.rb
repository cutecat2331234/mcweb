# frozen_string_literal: true

class AddReporterCaseLifecycle < ActiveRecord::Migration[8.1]
  REPORT_STATUS_CHECK = <<~SQL.squish.freeze
    status IN ('pending', 'withdrawn', 'reviewed', 'dismissed', 'actioned')
  SQL
  REPORT_OUTCOME_CHECK = <<~SQL.squish.freeze
    (status = 'pending' AND public_outcome_code IS NULL AND withdrawn_at IS NULL) OR
    (status = 'withdrawn' AND public_outcome_code IS NOT NULL AND public_outcome_code = 'withdrawn' AND withdrawn_at IS NOT NULL) OR
    (status = 'reviewed' AND public_outcome_code IS NOT NULL AND public_outcome_code = 'review_complete' AND withdrawn_at IS NULL) OR
    (status = 'dismissed' AND public_outcome_code IS NOT NULL AND public_outcome_code = 'not_upheld' AND withdrawn_at IS NULL) OR
    (status = 'actioned' AND public_outcome_code IS NOT NULL AND public_outcome_code = 'action_taken' AND withdrawn_at IS NULL)
  SQL
  STAFF_OUTCOME_CODES = "public_outcome_code IN ('review_complete', 'not_upheld', 'action_taken')"
  DIGEST_FORMAT = "idempotency_key_digest ~ '^[0-9a-f]{64}$'"

  def up
    add_report_lifecycle_columns
    backfill_report_lifecycle
    add_report_constraints
    create_report_supplements
    create_report_outcome_deliveries
    create_report_decision_batches
    create_append_only_triggers
  end

  def down
    drop_append_only_triggers
    drop_table :forum_report_decision_batches, if_exists: true
    drop_table :forum_report_outcome_deliveries, if_exists: true
    drop_table :forum_report_supplements, if_exists: true
    remove_check_constraint :forum_reports, name: "forum_reports_public_outcome_shape", if_exists: true
    remove_check_constraint :forum_reports, name: "forum_reports_status_vocabulary", if_exists: true
    remove_check_constraint :forum_reports, name: "forum_reports_withdrawal_digest", if_exists: true
    remove_index :forum_reports, name: "idx_forum_reports_reporter_created", if_exists: true
    remove_column :forum_reports, :withdrawal_idempotency_key_digest, if_exists: true
    remove_column :forum_reports, :withdrawn_at, if_exists: true
    remove_column :forum_reports, :public_outcome_code, if_exists: true
    remove_column :forum_reports, :state_changed_at, if_exists: true
    remove_column :forum_reports, :lock_version, if_exists: true
  end

  private

  def add_report_lifecycle_columns
    add_column :forum_reports, :lock_version, :integer, null: false, default: 0, if_not_exists: true
    add_column :forum_reports, :state_changed_at, :datetime, if_not_exists: true
    add_column :forum_reports, :public_outcome_code, :string, if_not_exists: true
    add_column :forum_reports, :withdrawn_at, :datetime, if_not_exists: true
    add_column :forum_reports,
      :withdrawal_idempotency_key_digest,
      :string,
      limit: 64,
      if_not_exists: true
    add_index :forum_reports,
      %i[reporter_id created_at],
      name: "idx_forum_reports_reporter_created",
      if_not_exists: true
  end

  def backfill_report_lifecycle
    execute <<~SQL.squish
      UPDATE forum_reports
      SET state_changed_at = COALESCE(reviewed_at, updated_at, created_at, CURRENT_TIMESTAMP),
          public_outcome_code = CASE status
            WHEN 'reviewed' THEN 'review_complete'
            WHEN 'dismissed' THEN 'not_upheld'
            WHEN 'actioned' THEN 'action_taken'
            ELSE NULL
          END
      WHERE state_changed_at IS NULL
         OR (status <> 'pending' AND public_outcome_code IS NULL)
    SQL
    change_column_null :forum_reports, :state_changed_at, false
  end

  def add_report_constraints
    add_check_constraint :forum_reports,
      REPORT_STATUS_CHECK,
      name: "forum_reports_status_vocabulary",
      validate: false,
      if_not_exists: true
    add_check_constraint :forum_reports,
      REPORT_OUTCOME_CHECK,
      name: "forum_reports_public_outcome_shape",
      validate: false,
      if_not_exists: true
    add_check_constraint :forum_reports,
      "withdrawal_idempotency_key_digest IS NULL OR " \
        "withdrawal_idempotency_key_digest ~ '^[0-9a-f]{64}$'",
      name: "forum_reports_withdrawal_digest",
      validate: false,
      if_not_exists: true
    validate_check_constraint :forum_reports, name: "forum_reports_status_vocabulary"
    validate_check_constraint :forum_reports, name: "forum_reports_public_outcome_shape"
    validate_check_constraint :forum_reports, name: "forum_reports_withdrawal_digest"
  end

  def create_report_supplements
    return if table_exists?(:forum_report_supplements)

    create_table :forum_report_supplements do |t|
      t.bigint :forum_report_id, null: false
      t.bigint :reporter_id, null: false
      t.text :body, null: false
      t.string :idempotency_key_digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index :forum_report_supplements,
      %i[forum_report_id idempotency_key_digest],
      unique: true,
      name: "idx_forum_report_supplements_idempotency"
    add_index :forum_report_supplements,
      %i[forum_report_id created_at],
      name: "idx_forum_report_supplements_report_created"
    add_index :forum_report_supplements, :reporter_id
    add_foreign_key :forum_report_supplements,
      :forum_reports,
      column: :forum_report_id,
      on_delete: :restrict
    add_foreign_key :forum_report_supplements,
      :users,
      column: :reporter_id,
      on_delete: :restrict
    add_check_constraint :forum_report_supplements,
      "char_length(btrim(body)) BETWEEN 1 AND 2000",
      name: "forum_report_supplements_body_length"
    add_check_constraint :forum_report_supplements,
      DIGEST_FORMAT,
      name: "forum_report_supplements_idempotency_digest"
  end

  def create_report_outcome_deliveries
    return if table_exists?(:forum_report_outcome_deliveries)

    create_table :forum_report_outcome_deliveries do |t|
      t.bigint :forum_report_id, null: false
      t.bigint :notification_id
      t.string :public_outcome_code, null: false
      t.string :idempotency_key_digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end
    add_index :forum_report_outcome_deliveries,
      :forum_report_id,
      unique: true,
      name: "idx_forum_report_outcome_deliveries_report"
    add_index :forum_report_outcome_deliveries,
      :notification_id,
      unique: true,
      where: "notification_id IS NOT NULL",
      name: "idx_forum_report_outcome_deliveries_notification"
    add_foreign_key :forum_report_outcome_deliveries,
      :forum_reports,
      column: :forum_report_id,
      on_delete: :restrict
    add_foreign_key :forum_report_outcome_deliveries,
      :notifications,
      column: :notification_id,
      on_delete: :nullify
    add_check_constraint :forum_report_outcome_deliveries,
      STAFF_OUTCOME_CODES,
      name: "forum_report_outcome_deliveries_outcome"
    add_check_constraint :forum_report_outcome_deliveries,
      DIGEST_FORMAT,
      name: "forum_report_outcome_deliveries_idempotency_digest"
  end

  def create_report_decision_batches
    return if table_exists?(:forum_report_decision_batches)

    create_table :forum_report_decision_batches do |t|
      t.string :idempotency_key_digest, null: false, limit: 64
      t.string :request_fingerprint, null: false, limit: 64
      t.bigint :reviewer_id, null: false
      t.string :reportable_type, null: false
      t.bigint :reportable_id, null: false
      t.string :desired_status, null: false
      t.jsonb :report_ids, null: false, default: []
      t.integer :decided_count, null: false
      t.datetime :created_at, null: false
    end
    add_index :forum_report_decision_batches,
      :idempotency_key_digest,
      unique: true,
      name: "idx_forum_report_decision_batches_idempotency"
    add_index :forum_report_decision_batches,
      %i[reportable_type reportable_id created_at],
      name: "idx_forum_report_decision_batches_target"
    add_foreign_key :forum_report_decision_batches,
      :users,
      column: :reviewer_id,
      on_delete: :restrict
    add_check_constraint :forum_report_decision_batches,
      DIGEST_FORMAT,
      name: "forum_report_decision_batches_idempotency_digest"
    add_check_constraint :forum_report_decision_batches,
      "request_fingerprint ~ '^[0-9a-f]{64}$'",
      name: "forum_report_decision_batches_request_fingerprint"
    add_check_constraint :forum_report_decision_batches,
      "desired_status IN ('reviewed', 'dismissed', 'actioned')",
      name: "forum_report_decision_batches_status"
    add_check_constraint :forum_report_decision_batches,
      "jsonb_typeof(report_ids) = 'array' AND decided_count = jsonb_array_length(report_ids) " \
        "AND decided_count >= 0",
      name: "forum_report_decision_batches_result_shape"
  end

  def create_append_only_triggers
    execute <<~SQL
      CREATE OR REPLACE FUNCTION forum_reports_guard_state_transition()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF OLD.status <> 'pending'
           AND NEW.status IS DISTINCT FROM OLD.status THEN
          RAISE EXCEPTION 'terminal forum report status cannot change';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_reports_state_transition_guard
      BEFORE UPDATE OF status ON forum_reports
      FOR EACH ROW
      EXECUTE FUNCTION forum_reports_guard_state_transition();

      CREATE OR REPLACE FUNCTION forum_report_supplements_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum report supplements are append-only';
      END;
      $$;

      CREATE OR REPLACE FUNCTION forum_report_supplements_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        owner_id bigint;
        report_status text;
      BEGIN
        SELECT reporter_id, status
        INTO owner_id, report_status
        FROM forum_reports
        WHERE id = NEW.forum_report_id
        FOR UPDATE;

        IF owner_id IS NULL
           OR owner_id <> NEW.reporter_id
           OR report_status <> 'pending' THEN
          RAISE EXCEPTION 'forum report supplement owner or state is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER forum_report_supplements_immutable
      BEFORE UPDATE OR DELETE ON forum_report_supplements
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_supplements_reject_change();

      CREATE TRIGGER forum_report_supplements_insert_contract
      BEFORE INSERT ON forum_report_supplements
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_supplements_validate_insert();

      CREATE OR REPLACE FUNCTION forum_report_outcome_deliveries_guard_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        IF TG_OP = 'UPDATE'
           AND OLD.notification_id IS NOT NULL
           AND NEW.notification_id IS NULL
           AND NEW.forum_report_id = OLD.forum_report_id
           AND NEW.public_outcome_code = OLD.public_outcome_code
           AND NEW.idempotency_key_digest = OLD.idempotency_key_digest
           AND NEW.created_at = OLD.created_at THEN
          RETURN NEW;
        END IF;

        RAISE EXCEPTION 'forum report outcome delivery receipts are immutable';
      END;
      $$;

      CREATE OR REPLACE FUNCTION forum_report_outcome_deliveries_validate_insert()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      DECLARE
        report_status text;
        report_outcome text;
        report_owner_id bigint;
        notification_owner_id bigint;
        notification_kind text;
        notification_metadata jsonb;
      BEGIN
        SELECT reports.status,
               reports.public_outcome_code,
               reports.reporter_id,
               notifications.user_id,
               notifications.notification_type,
               notifications.metadata
        INTO report_status,
             report_outcome,
             report_owner_id,
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
           OR notification_metadata ->> 'report_id' IS DISTINCT FROM NEW.forum_report_id::text
           OR notification_metadata ->> 'public_outcome_code' IS DISTINCT FROM NEW.public_outcome_code
           OR notification_metadata ->> 'path' IS DISTINCT FROM '/app/forum/reports/' || NEW.forum_report_id::text THEN
          RAISE EXCEPTION 'forum report outcome delivery contract is invalid';
        END IF;

        RETURN NEW;
      END;
      $$;

      CREATE OR REPLACE FUNCTION forum_report_decision_batches_reject_change()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $$
      BEGIN
        RAISE EXCEPTION 'forum report decision batches are immutable';
      END;
      $$;

      CREATE TRIGGER forum_report_outcome_deliveries_immutable
      BEFORE UPDATE OR DELETE ON forum_report_outcome_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_outcome_deliveries_guard_change();

      CREATE TRIGGER forum_report_outcome_deliveries_insert_contract
      BEFORE INSERT ON forum_report_outcome_deliveries
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_outcome_deliveries_validate_insert();

      CREATE TRIGGER forum_report_decision_batches_immutable
      BEFORE UPDATE OR DELETE ON forum_report_decision_batches
      FOR EACH ROW
      EXECUTE FUNCTION forum_report_decision_batches_reject_change();
    SQL
  end

  def drop_append_only_triggers
    if table_exists?(:forum_reports)
      execute "DROP TRIGGER IF EXISTS forum_reports_state_transition_guard ON forum_reports"
    end
    execute "DROP FUNCTION IF EXISTS forum_reports_guard_state_transition()"
    if table_exists?(:forum_report_decision_batches)
      execute "DROP TRIGGER IF EXISTS forum_report_decision_batches_immutable ON forum_report_decision_batches"
    end
    execute "DROP FUNCTION IF EXISTS forum_report_decision_batches_reject_change()"
    if table_exists?(:forum_report_supplements)
      execute "DROP TRIGGER IF EXISTS forum_report_supplements_immutable ON forum_report_supplements"
      execute "DROP TRIGGER IF EXISTS forum_report_supplements_insert_contract ON forum_report_supplements"
    end
    execute "DROP FUNCTION IF EXISTS forum_report_supplements_reject_change()"
    execute "DROP FUNCTION IF EXISTS forum_report_supplements_validate_insert()"
    if table_exists?(:forum_report_outcome_deliveries)
      execute "DROP TRIGGER IF EXISTS forum_report_outcome_deliveries_immutable ON forum_report_outcome_deliveries"
      execute "DROP TRIGGER IF EXISTS forum_report_outcome_deliveries_insert_contract ON forum_report_outcome_deliveries"
    end
    execute "DROP FUNCTION IF EXISTS forum_report_outcome_deliveries_guard_change()"
    execute "DROP FUNCTION IF EXISTS forum_report_outcome_deliveries_validate_insert()"
  end
end
