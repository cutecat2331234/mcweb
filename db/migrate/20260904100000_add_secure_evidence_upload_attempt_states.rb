# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddSecureEvidenceUploadAttemptStates < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  ATTACHMENT_STATE_CONSTRAINT = "secure_evidence_attachments_valid_state"
  EVENT_TYPE_CONSTRAINT = "secure_evidence_events_valid_type"
  UP_STATE_CONSTRAINT = "secure_evidence_states_with_upload_attempts"
  DOWN_STATE_CONSTRAINT = "secure_evidence_states_without_upload_attempts"
  UP_EVENT_CONSTRAINT = "secure_evidence_events_with_upload_attempts"
  DOWN_EVENT_CONSTRAINT = "secure_evidence_events_without_upload_attempts"
  UPDATE_FUNCTION = "secure_evidence_attachments_guard_update"

  BASE_STATES = %w[pending available quarantined purge_pending purged].freeze
  UPLOAD_STATES = %w[uploading upload_failed].freeze
  BASE_EVENTS = %w[
    created scan_clean scan_infected scan_error downloaded retention_extended
    discarded cleanup_scheduled cleanup_failed purged
  ].freeze
  UPLOAD_EVENTS = %w[upload_stored upload_failed upload_retried].freeze

  def up
    replace_check_constraint!(
      table: :secure_evidence_attachments,
      canonical_name: ATTACHMENT_STATE_CONSTRAINT,
      temporary_name: UP_STATE_CONSTRAINT,
      stale_temporary_name: DOWN_STATE_CONSTRAINT,
      values: UPLOAD_STATES + BASE_STATES,
      all_values: UPLOAD_STATES + BASE_STATES,
      column: :state
    )
    replace_check_constraint!(
      table: :secure_evidence_attachment_events,
      canonical_name: EVENT_TYPE_CONSTRAINT,
      temporary_name: UP_EVENT_CONSTRAINT,
      stale_temporary_name: DOWN_EVENT_CONSTRAINT,
      values: BASE_EVENTS + UPLOAD_EVENTS,
      all_values: BASE_EVENTS + UPLOAD_EVENTS,
      column: :event_type
    )
    install_update_guard!(allow_upload_attempts: true)
  end

  def down
    if connection.select_value(<<~SQL.squish)
      SELECT 1
      FROM secure_evidence_attachments
      WHERE state IN ('uploading', 'upload_failed')
      LIMIT 1
    SQL
      raise ActiveRecord::IrreversibleMigration,
        "finish or retain secure evidence upload attempts before removing their states"
    end
    if connection.select_value(<<~SQL.squish)
      SELECT 1
      FROM secure_evidence_attachment_events
      WHERE event_type IN ('upload_stored', 'upload_failed', 'upload_retried')
      LIMIT 1
    SQL
      raise ActiveRecord::IrreversibleMigration,
        "secure evidence upload-attempt events are immutable"
    end

    install_update_guard!(allow_upload_attempts: false)
    replace_check_constraint!(
      table: :secure_evidence_attachment_events,
      canonical_name: EVENT_TYPE_CONSTRAINT,
      temporary_name: DOWN_EVENT_CONSTRAINT,
      stale_temporary_name: UP_EVENT_CONSTRAINT,
      values: BASE_EVENTS,
      all_values: BASE_EVENTS + UPLOAD_EVENTS,
      column: :event_type
    )
    replace_check_constraint!(
      table: :secure_evidence_attachments,
      canonical_name: ATTACHMENT_STATE_CONSTRAINT,
      temporary_name: DOWN_STATE_CONSTRAINT,
      stale_temporary_name: UP_STATE_CONSTRAINT,
      values: BASE_STATES,
      all_values: UPLOAD_STATES + BASE_STATES,
      column: :state
    )
  end

  private

  def replace_check_constraint!(
    table:,
    canonical_name:,
    temporary_name:,
    stale_temporary_name:,
    values:,
    all_values:,
    column:
  )
    canonical_definition = constraint_definition(table, canonical_name)
    if canonical_definition && definition_matches?(canonical_definition, values, all_values)
      validate_check_constraint table, name: canonical_name unless
        constraint_validated?(table, canonical_name)
      remove_check_constraint table, name: temporary_name, if_exists: true
      remove_check_constraint table, name: stale_temporary_name, if_exists: true
      return
    end

    remove_check_constraint table, name: stale_temporary_name, if_exists: true
    temporary_definition = constraint_definition(table, temporary_name)
    unless temporary_definition && definition_matches?(temporary_definition, values, all_values)
      remove_check_constraint table, name: temporary_name, if_exists: true
      add_check_constraint table,
        "#{connection.quote_column_name(column)} IN (#{quoted_values(values)})",
        name: temporary_name,
        validate: false
    end
    validate_check_constraint table, name: temporary_name unless
      constraint_validated?(table, temporary_name)
    remove_check_constraint table, name: canonical_name, if_exists: true
    rename_constraint(table, temporary_name, canonical_name)
  end

  def definition_matches?(definition, values, all_values)
    values.all? { |value| definition.include?(value) } &&
      (all_values - values).none? { |value| definition.include?(value) }
  end

  def quoted_values(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end

  def rename_constraint(table, from, to)
    return unless check_constraint_exists?(table, name: from)
    return if check_constraint_exists?(table, name: to)

    execute <<~SQL.squish
      ALTER TABLE #{connection.quote_table_name(table)}
      RENAME CONSTRAINT #{connection.quote_column_name(from)}
      TO #{connection.quote_column_name(to)}
    SQL
  end

  def install_update_guard!(allow_upload_attempts:)
    transitions = if allow_upload_attempts
      <<~SQL.squish
        (OLD.state = 'uploading' AND NEW.state IN ('uploading', 'pending', 'upload_failed', 'purge_pending'))
        OR (OLD.state = 'upload_failed' AND NEW.state IN ('upload_failed', 'uploading', 'purge_pending'))
        OR
      SQL
    else
      ""
    end

    execute <<~SQL
      CREATE OR REPLACE FUNCTION #{UPDATE_FUNCTION}()
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
          #{transitions}
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
    SQL
  end
end
