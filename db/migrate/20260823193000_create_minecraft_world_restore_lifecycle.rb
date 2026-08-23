# frozen_string_literal: true

class CreateMinecraftWorldRestoreLifecycle < ActiveRecord::Migration[8.1]
  ACTIVE_RESTORE_STATUSES = %w[planned authorized queued running recovery_required].freeze

  def up
    create_world_backups
    create_world_restore_plans
    create_world_restore_events
    create_immutability_triggers
    retire_legacy_world_tasks
  end

  def down
    drop_immutability_triggers
    drop_table :minecraft_world_restore_events
    drop_table :minecraft_world_restore_plans
    drop_table :minecraft_world_backups
  end

  private

  def create_world_backups
    create_table :minecraft_world_backups do |t|
      t.string :public_id, null: false
      t.references :minecraft_server, null: false, foreign_key: true
      t.references :minecraft_node, null: false, foreign_key: true
      t.references :minecraft_node_operation, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :purpose, null: false
      t.string :status, null: false, default: "requested"
      t.string :request_id, null: false, limit: 36
      t.string :request_digest, null: false, limit: 64
      t.integer :manifest_version
      t.string :safety_profile
      t.string :archive_format
      t.string :manifest_digest, limit: 64
      t.string :archive_sha256, limit: 64
      t.bigint :archive_bytes
      t.bigint :uncompressed_bytes
      t.bigint :entry_count
      t.jsonb :manifest_summary, null: false, default: {}
      t.datetime :verified_at
      t.datetime :failed_at
      t.string :error_code
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :minecraft_world_backups, :public_id, unique: true
    add_index :minecraft_world_backups, :request_id, unique: true
    add_index :minecraft_world_backups, :minecraft_node_operation_id,
      unique: true,
      where: "minecraft_node_operation_id IS NOT NULL",
      name: "idx_minecraft_world_backups_operation"
    add_index :minecraft_world_backups, %i[minecraft_server_id status created_at],
      name: "idx_minecraft_world_backups_server_status"
    add_check_constraint :minecraft_world_backups,
      "purpose IN ('manual', 'scheduled', 'pre_restore')",
      name: "chk_minecraft_world_backups_purpose"
    add_check_constraint :minecraft_world_backups,
      "status IN ('requested', 'queued', 'creating', 'available', 'failed', 'quarantined')",
      name: "chk_minecraft_world_backups_status"
    add_check_constraint :minecraft_world_backups,
      "request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "chk_minecraft_world_backups_request_id"
    add_check_constraint :minecraft_world_backups,
      "request_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_world_backups_request_digest"
    add_check_constraint :minecraft_world_backups,
      "manifest_digest IS NULL OR manifest_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_world_backups_manifest_digest"
    add_check_constraint :minecraft_world_backups,
      "archive_sha256 IS NULL OR archive_sha256 ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_world_backups_archive_sha256"
    add_check_constraint :minecraft_world_backups,
      "archive_bytes IS NULL OR archive_bytes >= 0",
      name: "chk_minecraft_world_backups_archive_bytes"
    add_check_constraint :minecraft_world_backups,
      "uncompressed_bytes IS NULL OR uncompressed_bytes >= 0",
      name: "chk_minecraft_world_backups_uncompressed_bytes"
    add_check_constraint :minecraft_world_backups,
      "entry_count IS NULL OR entry_count >= 0",
      name: "chk_minecraft_world_backups_entry_count"
  end

  def create_world_restore_plans
    create_table :minecraft_world_restore_plans do |t|
      t.string :public_id, null: false
      t.references :minecraft_server, null: false, foreign_key: true
      t.references :minecraft_node, null: false, foreign_key: true
      t.references :minecraft_world_backup, null: false, foreign_key: true
      t.references :pre_restore_world_backup,
        foreign_key: { to_table: :minecraft_world_backups },
        index: { name: "idx_minecraft_restore_plans_pre_backup" }
      t.references :minecraft_node_operation, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "planned"
      t.text :reason, null: false
      t.string :request_id, null: false, limit: 36
      t.string :request_digest, null: false, limit: 64
      t.string :plan_digest, null: false, limit: 64
      t.string :backup_manifest_digest, null: false, limit: 64
      t.string :server_configuration_digest, null: false, limit: 64
      t.string :node_capability_digest, null: false, limit: 64
      t.datetime :frozen_server_updated_at, null: false
      t.string :world_relative_path, null: false, limit: 1024
      t.datetime :expires_at, null: false
      t.string :authorization_digest, limit: 64
      t.string :authorization_method
      t.datetime :authorization_expires_at
      t.datetime :authorized_at
      t.datetime :authorization_consumed_at
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :failed_at
      t.string :error_code
      t.jsonb :result_summary, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :minecraft_world_restore_plans, :public_id, unique: true
    add_index :minecraft_world_restore_plans, :request_id, unique: true
    add_index :minecraft_world_restore_plans, :minecraft_node_operation_id,
      unique: true,
      where: "minecraft_node_operation_id IS NOT NULL",
      name: "idx_minecraft_restore_plans_operation"
    add_index :minecraft_world_restore_plans, %i[minecraft_server_id status created_at],
      name: "idx_minecraft_restore_plans_server_status"
    add_index :minecraft_world_restore_plans,
      :minecraft_server_id,
      unique: true,
      where: "status IN (#{ACTIVE_RESTORE_STATUSES.map { |status| quote(status) }.join(', ')})",
      name: "idx_minecraft_restore_plans_one_active"
    add_check_constraint :minecraft_world_restore_plans,
      "status IN ('planned', 'authorized', 'queued', 'running', 'completed', 'failed', 'rolled_back', 'recovery_required', 'expired', 'cancelled')",
      name: "chk_minecraft_world_restore_plans_status"
    add_check_constraint :minecraft_world_restore_plans,
      "char_length(reason) BETWEEN 1 AND 1000",
      name: "chk_minecraft_world_restore_plans_reason"
    add_check_constraint :minecraft_world_restore_plans,
      "request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "chk_minecraft_world_restore_plans_request_id"
    %i[request_digest plan_digest backup_manifest_digest server_configuration_digest node_capability_digest].each do |column|
      add_check_constraint :minecraft_world_restore_plans,
        "#{column} ~ '^[0-9a-f]{64}$'",
        name: "chk_minecraft_restore_plans_#{column.to_s.sub('_digest', '')}"
    end
    add_check_constraint :minecraft_world_restore_plans,
      "authorization_digest IS NULL OR authorization_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_restore_plans_authorization"
    add_check_constraint :minecraft_world_restore_plans,
      "authorization_method IS NULL OR authorization_method IN ('password', 'totp', 'recovery_code')",
      name: "chk_minecraft_restore_plans_auth_method"
  end

  def create_world_restore_events
    create_table :minecraft_world_restore_events, id: :bigserial do |t|
      t.references :minecraft_world_restore_plan,
        null: false,
        foreign_key: true,
        index: { name: "idx_minecraft_restore_events_plan" }
      t.references :actor, foreign_key: { to_table: :users }
      t.integer :sequence, null: false
      t.string :event_type, null: false
      t.string :phase, null: false
      t.jsonb :payload_summary, null: false, default: {}
      t.string :payload_digest, null: false, limit: 64
      t.datetime :created_at, null: false
    end

    add_index :minecraft_world_restore_events,
      %i[minecraft_world_restore_plan_id sequence],
      unique: true,
      name: "idx_minecraft_restore_events_sequence"
    add_check_constraint :minecraft_world_restore_events,
      "sequence > 0",
      name: "chk_minecraft_restore_events_sequence"
    add_check_constraint :minecraft_world_restore_events,
      "payload_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_restore_events_digest"
    add_check_constraint :minecraft_world_restore_events,
      "event_type ~ '^minecraft\\.world_restore\\.[a-z0-9_]+$'",
      name: "chk_minecraft_restore_events_type"
    add_check_constraint :minecraft_world_restore_events,
      "phase IN ('planned', 'authorized', 'queued', 'running', 'accepted', 'process_stopped', 'pre_snapshot_started', 'pre_snapshot_durable', 'archive_validated', 'staging_started', 'staging_verified', 'live_preserved', 'replacement_installed', 'post_install_verified', 'rollback_started', 'rolled_back', 'completed', 'failed', 'recovery_required', 'expired', 'cancelled')",
      name: "chk_minecraft_restore_events_phase"
  end

  def create_immutability_triggers
    execute <<~SQL
      CREATE OR REPLACE FUNCTION minecraft_world_restore_events_immutable_fn()
      RETURNS trigger AS $$
      BEGIN
        RAISE EXCEPTION 'minecraft world restore events are append-only';
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER minecraft_world_restore_events_immutable
      BEFORE UPDATE OR DELETE ON minecraft_world_restore_events
      FOR EACH ROW EXECUTE FUNCTION minecraft_world_restore_events_immutable_fn();

      CREATE OR REPLACE FUNCTION minecraft_world_backups_immutable_fn()
      RETURNS trigger AS $$
      BEGIN
        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.minecraft_server_id IS DISTINCT FROM NEW.minecraft_server_id
          OR OLD.minecraft_node_id IS DISTINCT FROM NEW.minecraft_node_id
          OR OLD.created_by_id IS DISTINCT FROM NEW.created_by_id
          OR OLD.purpose IS DISTINCT FROM NEW.purpose
          OR OLD.request_id IS DISTINCT FROM NEW.request_id
          OR OLD.request_digest IS DISTINCT FROM NEW.request_digest THEN
          RAISE EXCEPTION 'minecraft world backup identity is immutable';
        END IF;

        IF OLD.status IN ('available', 'quarantined') AND (
          OLD.manifest_version IS DISTINCT FROM NEW.manifest_version
          OR OLD.safety_profile IS DISTINCT FROM NEW.safety_profile
          OR OLD.archive_format IS DISTINCT FROM NEW.archive_format
          OR OLD.manifest_digest IS DISTINCT FROM NEW.manifest_digest
          OR OLD.archive_sha256 IS DISTINCT FROM NEW.archive_sha256
          OR OLD.archive_bytes IS DISTINCT FROM NEW.archive_bytes
          OR OLD.uncompressed_bytes IS DISTINCT FROM NEW.uncompressed_bytes
          OR OLD.entry_count IS DISTINCT FROM NEW.entry_count
          OR OLD.manifest_summary IS DISTINCT FROM NEW.manifest_summary
        ) THEN
          RAISE EXCEPTION 'verified minecraft world backup manifest is immutable';
        END IF;
        IF OLD.minecraft_node_operation_id IS NOT NULL
          AND OLD.minecraft_node_operation_id IS DISTINCT FROM NEW.minecraft_node_operation_id THEN
          RAISE EXCEPTION 'minecraft world backup operation binding is immutable';
        END IF;
        IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
          (OLD.status = 'requested' AND NEW.status IN ('queued', 'failed'))
          OR (OLD.status = 'queued' AND NEW.status IN ('creating', 'available', 'failed'))
          OR (OLD.status = 'creating' AND NEW.status IN ('available', 'failed'))
          OR (OLD.status = 'available' AND NEW.status = 'quarantined')
        ) THEN
          RAISE EXCEPTION 'invalid minecraft world backup state transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER minecraft_world_backups_immutable
      BEFORE UPDATE ON minecraft_world_backups
      FOR EACH ROW EXECUTE FUNCTION minecraft_world_backups_immutable_fn();

      CREATE OR REPLACE FUNCTION minecraft_world_restore_plans_immutable_fn()
      RETURNS trigger AS $$
      BEGIN
        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.minecraft_server_id IS DISTINCT FROM NEW.minecraft_server_id
          OR OLD.minecraft_node_id IS DISTINCT FROM NEW.minecraft_node_id
          OR OLD.minecraft_world_backup_id IS DISTINCT FROM NEW.minecraft_world_backup_id
          OR OLD.actor_id IS DISTINCT FROM NEW.actor_id
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.request_id IS DISTINCT FROM NEW.request_id
          OR OLD.request_digest IS DISTINCT FROM NEW.request_digest
          OR OLD.plan_digest IS DISTINCT FROM NEW.plan_digest
          OR OLD.backup_manifest_digest IS DISTINCT FROM NEW.backup_manifest_digest
          OR OLD.server_configuration_digest IS DISTINCT FROM NEW.server_configuration_digest
          OR OLD.node_capability_digest IS DISTINCT FROM NEW.node_capability_digest
          OR OLD.frozen_server_updated_at IS DISTINCT FROM NEW.frozen_server_updated_at
          OR OLD.world_relative_path IS DISTINCT FROM NEW.world_relative_path
          OR OLD.expires_at IS DISTINCT FROM NEW.expires_at THEN
          RAISE EXCEPTION 'minecraft world restore plan is immutable';
        END IF;
        IF (OLD.pre_restore_world_backup_id IS NOT NULL
            AND OLD.pre_restore_world_backup_id IS DISTINCT FROM NEW.pre_restore_world_backup_id)
          OR (OLD.minecraft_node_operation_id IS NOT NULL
            AND OLD.minecraft_node_operation_id IS DISTINCT FROM NEW.minecraft_node_operation_id) THEN
          RAISE EXCEPTION 'minecraft world restore execution binding is immutable';
        END IF;
        IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
          (OLD.status = 'planned' AND NEW.status IN ('authorized', 'expired', 'cancelled'))
          OR (OLD.status = 'authorized' AND NEW.status IN ('queued', 'expired', 'cancelled'))
          OR (OLD.status IN ('queued', 'running')
            AND NEW.status IN ('running', 'completed', 'failed', 'rolled_back', 'recovery_required'))
        ) THEN
          RAISE EXCEPTION 'invalid minecraft world restore state transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER minecraft_world_restore_plans_immutable
      BEFORE UPDATE ON minecraft_world_restore_plans
      FOR EACH ROW EXECUTE FUNCTION minecraft_world_restore_plans_immutable_fn();
    SQL
  end

  def drop_immutability_triggers
    execute "DROP TRIGGER IF EXISTS minecraft_world_restore_plans_immutable ON minecraft_world_restore_plans"
    execute "DROP FUNCTION IF EXISTS minecraft_world_restore_plans_immutable_fn()"
    execute "DROP TRIGGER IF EXISTS minecraft_world_backups_immutable ON minecraft_world_backups"
    execute "DROP FUNCTION IF EXISTS minecraft_world_backups_immutable_fn()"
    execute "DROP TRIGGER IF EXISTS minecraft_world_restore_events_immutable ON minecraft_world_restore_events"
    execute "DROP FUNCTION IF EXISTS minecraft_world_restore_events_immutable_fn()"
  end

  def retire_legacy_world_tasks
    execute <<~SQL
      UPDATE minecraft_node_tasks
      SET status = 'failed',
          result = COALESCE(result, '{}'::jsonb) || '{"success":false,"status":"failed","error_code":"legacy_world_operation_retired"}'::jsonb,
          completed_at = COALESCE(completed_at, CURRENT_TIMESTAMP),
          updated_at = CURRENT_TIMESTAMP
      WHERE task_type IN ('backup_world', 'restore_world')
        AND status IN ('pending', 'claimed')
    SQL
  end
end
