# frozen_string_literal: true

class CloseMinecraftWorldRestoreP1Gaps < ActiveRecord::Migration[8.1]
  ACTIVE_RESOLUTION_STATUSES = %w[planned authorized queued running].freeze
  PERMISSION_KEY = "minecraft.world_restores.resolve_recovery"

  def up
    create_recovery_resolutions
    create_resolution_immutability_trigger
    replace_world_backup_immutability_trigger(allow_node_proven_snapshot_recovery: true)
    replace_restore_plan_immutability_trigger(allow_proven_resolution: true)
    install_permission
  end

  def down
    remove_permission
    replace_restore_plan_immutability_trigger(allow_proven_resolution: false)
    replace_world_backup_immutability_trigger(allow_node_proven_snapshot_recovery: false)
    execute "DROP TRIGGER IF EXISTS minecraft_world_restore_resolutions_immutable ON minecraft_world_restore_resolutions"
    execute "DROP FUNCTION IF EXISTS minecraft_world_restore_resolutions_immutable_fn()"
    drop_table :minecraft_world_restore_resolutions
  end

  private

  def create_recovery_resolutions
    create_table :minecraft_world_restore_resolutions do |t|
      t.string :public_id, null: false
      t.references :minecraft_world_restore_plan,
        null: false,
        foreign_key: true,
        index: { name: "idx_minecraft_restore_resolutions_plan" }
      t.references :minecraft_node_operation, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.string :status, null: false, default: "planned"
      t.string :resolution_action, null: false
      t.text :reason, null: false
      t.string :request_id, null: false, limit: 36
      t.string :request_digest, null: false, limit: 64
      t.integer :expected_plan_lock_version, null: false
      t.string :plan_digest, null: false, limit: 64
      t.string :server_configuration_digest, null: false, limit: 64
      t.string :node_capability_digest, null: false, limit: 64
      t.string :pre_restore_manifest_digest, limit: 64
      t.string :authorization_digest, limit: 64
      t.string :authorization_method
      t.datetime :authorization_expires_at
      t.datetime :authorized_at
      t.datetime :authorization_consumed_at
      t.datetime :queued_at
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_code
      t.jsonb :result_summary, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end

    add_index :minecraft_world_restore_resolutions, :public_id, unique: true
    add_index :minecraft_world_restore_resolutions, :request_id, unique: true
    add_index :minecraft_world_restore_resolutions,
      :minecraft_node_operation_id,
      unique: true,
      where: "minecraft_node_operation_id IS NOT NULL",
      name: "idx_minecraft_restore_resolutions_operation"
    add_index :minecraft_world_restore_resolutions,
      :minecraft_world_restore_plan_id,
      unique: true,
      where: "status IN (#{ACTIVE_RESOLUTION_STATUSES.map { |status| connection.quote(status) }.join(', ')})",
      name: "idx_minecraft_restore_resolutions_one_active"
    add_check_constraint :minecraft_world_restore_resolutions,
      "status IN ('planned', 'authorized', 'queued', 'running', 'completed', 'failed', 'recovery_required')",
      name: "chk_minecraft_restore_resolutions_status"
    add_check_constraint :minecraft_world_restore_resolutions,
      "resolution_action IN ('resume', 'rollback', 'reconcile')",
      name: "chk_minecraft_restore_resolutions_action"
    add_check_constraint :minecraft_world_restore_resolutions,
      "char_length(reason) BETWEEN 1 AND 1000",
      name: "chk_minecraft_restore_resolutions_reason"
    add_check_constraint :minecraft_world_restore_resolutions,
      "request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'",
      name: "chk_minecraft_restore_resolutions_request_id"
    add_check_constraint :minecraft_world_restore_resolutions,
      "expected_plan_lock_version >= 0",
      name: "chk_minecraft_restore_resolutions_plan_lock"
    %i[request_digest plan_digest server_configuration_digest node_capability_digest].each do |column|
      add_check_constraint :minecraft_world_restore_resolutions,
        "#{column} ~ '^[0-9a-f]{64}$'",
        name: "chk_minecraft_restore_resolutions_#{column.to_s.sub('_digest', '')}"
    end
    add_check_constraint :minecraft_world_restore_resolutions,
      "pre_restore_manifest_digest IS NULL OR pre_restore_manifest_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_restore_resolutions_pre_manifest"
    add_check_constraint :minecraft_world_restore_resolutions,
      "authorization_digest IS NULL OR authorization_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_minecraft_restore_resolutions_authorization"
    add_check_constraint :minecraft_world_restore_resolutions,
      "authorization_method IS NULL OR authorization_method IN ('password', 'totp', 'recovery_code')",
      name: "chk_minecraft_restore_resolutions_auth_method"
  end

  def create_resolution_immutability_trigger
    execute <<~SQL
      CREATE OR REPLACE FUNCTION minecraft_world_restore_resolutions_immutable_fn()
      RETURNS trigger AS $$
      BEGIN
        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.minecraft_world_restore_plan_id IS DISTINCT FROM NEW.minecraft_world_restore_plan_id
          OR OLD.actor_id IS DISTINCT FROM NEW.actor_id
          OR OLD.resolution_action IS DISTINCT FROM NEW.resolution_action
          OR OLD.reason IS DISTINCT FROM NEW.reason
          OR OLD.request_id IS DISTINCT FROM NEW.request_id
          OR OLD.request_digest IS DISTINCT FROM NEW.request_digest
          OR OLD.expected_plan_lock_version IS DISTINCT FROM NEW.expected_plan_lock_version
          OR OLD.plan_digest IS DISTINCT FROM NEW.plan_digest
          OR OLD.server_configuration_digest IS DISTINCT FROM NEW.server_configuration_digest
          OR OLD.node_capability_digest IS DISTINCT FROM NEW.node_capability_digest
          OR OLD.pre_restore_manifest_digest IS DISTINCT FROM NEW.pre_restore_manifest_digest THEN
          RAISE EXCEPTION 'minecraft world restore resolution contract is immutable';
        END IF;
        IF OLD.minecraft_node_operation_id IS NOT NULL
          AND OLD.minecraft_node_operation_id IS DISTINCT FROM NEW.minecraft_node_operation_id THEN
          RAISE EXCEPTION 'minecraft world restore resolution operation binding is immutable';
        END IF;
        IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
          (OLD.status = 'planned' AND NEW.status IN ('authorized', 'failed'))
          OR (OLD.status = 'authorized' AND NEW.status IN ('queued', 'failed'))
          OR (OLD.status IN ('queued', 'running')
            AND NEW.status IN ('running', 'completed', 'failed', 'recovery_required'))
        ) THEN
          RAISE EXCEPTION 'invalid minecraft world restore resolution state transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER minecraft_world_restore_resolutions_immutable
      BEFORE UPDATE ON minecraft_world_restore_resolutions
      FOR EACH ROW EXECUTE FUNCTION minecraft_world_restore_resolutions_immutable_fn();
    SQL
  end

  def replace_restore_plan_immutability_trigger(allow_proven_resolution:)
    resolution_transition = if allow_proven_resolution
      <<~SQL.squish
        OR (OLD.status = 'recovery_required'
          AND NEW.status IN ('completed', 'rolled_back')
          AND EXISTS (
            SELECT 1
            FROM minecraft_world_restore_resolutions resolution
            WHERE resolution.minecraft_world_restore_plan_id = NEW.id
              AND resolution.status = 'completed'
              AND resolution.result_summary->>'recovery_resolution_proof' = 'true'
              AND resolution.result_summary->>'plan_id' = NEW.public_id
              AND resolution.result_summary->>'phase' = NEW.status
          ))
      SQL
    else
      ""
    end

    execute <<~SQL
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
          #{resolution_transition}
        ) THEN
          RAISE EXCEPTION 'invalid minecraft world restore state transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def replace_world_backup_immutability_trigger(allow_node_proven_snapshot_recovery:)
    recovered_snapshot_transition = if allow_node_proven_snapshot_recovery
      <<~SQL.squish
        OR (OLD.status = 'failed'
          AND NEW.status = 'available'
          AND OLD.purpose = 'pre_restore'
          AND EXISTS (
            SELECT 1
            FROM minecraft_world_restore_plans restore_plan
            INNER JOIN minecraft_world_restore_resolutions resolution
              ON resolution.minecraft_world_restore_plan_id = restore_plan.id
            WHERE restore_plan.pre_restore_world_backup_id = NEW.id
              AND resolution.status IN ('queued', 'running')
              AND resolution.minecraft_node_operation_id IS NOT NULL
          ))
      SQL
    else
      ""
    end

    execute <<~SQL
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
          #{recovered_snapshot_transition}
        ) THEN
          RAISE EXCEPTION 'invalid minecraft world backup state transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def install_permission
    execute <<~SQL
      INSERT INTO permissions (key, name, category, description, created_at, updated_at)
      VALUES (
        #{connection.quote(PERMISSION_KEY)},
        'Resolve Minecraft world restore recovery',
        'minecraft',
        'Authorize node-proven resolution of a recovery-required world restore',
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
      )
      ON CONFLICT (key) DO NOTHING
    SQL
  end

  def remove_permission
    execute <<~SQL
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key = #{connection.quote(PERMISSION_KEY)});
      DELETE FROM permissions WHERE key = #{connection.quote(PERMISSION_KEY)};
    SQL
  end
end
