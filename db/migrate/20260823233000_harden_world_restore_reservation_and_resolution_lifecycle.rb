# frozen_string_literal: true

class HardenWorldRestoreReservationAndResolutionLifecycle < ActiveRecord::Migration[8.1]
  OLD_RESOLUTION_STATUSES = %w[
    planned authorized queued running completed failed recovery_required
  ].freeze
  NEW_RESOLUTION_STATUSES = (OLD_RESOLUTION_STATUSES + %w[expired cancelled taken_over]).freeze

  def up
    create_sensitive_action_reservations
    extend_recovery_resolution_lifecycle
    replace_resolution_trigger(NEW_RESOLUTION_STATUSES)
  end

  def down
    execute "DROP TRIGGER IF EXISTS minecraft_world_restore_resolutions_immutable ON minecraft_world_restore_resolutions"
    remove_check_constraint :minecraft_world_restore_resolutions,
      name: "chk_minecraft_restore_resolutions_lifecycle"
    execute <<~SQL
      UPDATE minecraft_world_restore_resolutions
      SET status = 'recovery_required'
      WHERE status IN ('expired', 'cancelled', 'taken_over')
    SQL
    replace_resolution_trigger(OLD_RESOLUTION_STATUSES)
    contract = foreign_key_exists?(
      :minecraft_world_restore_resolutions,
      :minecraft_world_restore_resolutions,
      column: :supersedes_resolution_id
    )
    remove_foreign_key :minecraft_world_restore_resolutions,
      column: :supersedes_resolution_id if contract
    remove_foreign_key :minecraft_world_restore_resolutions,
      column: :lifecycle_actor_id if foreign_key_exists?(
        :minecraft_world_restore_resolutions,
        :users,
        column: :lifecycle_actor_id
      )
    remove_check_constraint :minecraft_world_restore_resolutions,
      name: "chk_minecraft_restore_resolutions_expires"
    remove_check_constraint :minecraft_world_restore_resolutions,
      name: "chk_minecraft_restore_resolutions_status"
    add_check_constraint :minecraft_world_restore_resolutions,
      "status IN (#{quoted(OLD_RESOLUTION_STATUSES)})",
      name: "chk_minecraft_restore_resolutions_status"
    remove_index :minecraft_world_restore_resolutions,
      name: "idx_minecraft_restore_resolutions_lifecycle_request"
    remove_index :minecraft_world_restore_resolutions,
      name: "idx_minecraft_restore_resolutions_supersedes"
    remove_index :minecraft_world_restore_resolutions,
      name: "idx_minecraft_restore_resolutions_expires"
    %i[
      supersedes_resolution_id lifecycle_actor_id lifecycle_action lifecycle_reason
      lifecycle_request_id lifecycle_request_digest lifecycle_authorization_method
      lifecycle_authorized_at lifecycle_completed_at expired_at expires_at
    ].each do |column|
      remove_column :minecraft_world_restore_resolutions, column
    end
    drop_sensitive_action_reservations
  end

  private

  def create_sensitive_action_reservations
    create_table :sensitive_action_rate_limit_reservations do |t|
      t.string :public_id, null: false
      t.string :scope, null: false
      t.references :user, null: false, foreign_key: true
      t.string :user_counter_key, null: false
      t.string :ip_counter_key, null: false
      t.string :context_digest, null: false, limit: 64
      t.string :status, null: false, default: "pending"
      t.integer :limit, null: false
      t.integer :window_seconds, null: false
      t.datetime :expires_at, null: false
      t.datetime :settled_at
      t.timestamps
    end
    add_index :sensitive_action_rate_limit_reservations, :public_id, unique: true
    add_index :sensitive_action_rate_limit_reservations,
      %i[status expires_at],
      name: "idx_sensitive_action_reservations_active"
    add_index :sensitive_action_rate_limit_reservations,
      %i[user_counter_key status expires_at],
      name: "idx_sensitive_action_reservations_user_bucket"
    add_index :sensitive_action_rate_limit_reservations,
      %i[ip_counter_key status expires_at],
      name: "idx_sensitive_action_reservations_ip_bucket"
    add_check_constraint :sensitive_action_rate_limit_reservations,
      "status IN ('pending', 'succeeded', 'failed')",
      name: "chk_sensitive_action_reservations_status"
    add_check_constraint :sensitive_action_rate_limit_reservations,
      "context_digest ~ '^[0-9a-f]{64}$'",
      name: "chk_sensitive_action_reservations_context"
    add_check_constraint :sensitive_action_rate_limit_reservations,
      "limit > 0 AND window_seconds > 0",
      name: "chk_sensitive_action_reservations_limits"
    add_check_constraint :sensitive_action_rate_limit_reservations,
      "(status = 'pending' AND settled_at IS NULL) OR (status IN ('succeeded', 'failed') AND settled_at IS NOT NULL)",
      name: "chk_sensitive_action_reservations_settlement"

    execute <<~SQL
      CREATE FUNCTION sensitive_action_rate_limit_reservations_immutable_fn()
      RETURNS trigger AS $$
      BEGIN
        IF OLD.public_id IS DISTINCT FROM NEW.public_id
          OR OLD.scope IS DISTINCT FROM NEW.scope
          OR OLD.user_id IS DISTINCT FROM NEW.user_id
          OR OLD.user_counter_key IS DISTINCT FROM NEW.user_counter_key
          OR OLD.ip_counter_key IS DISTINCT FROM NEW.ip_counter_key
          OR OLD.context_digest IS DISTINCT FROM NEW.context_digest
          OR OLD.limit IS DISTINCT FROM NEW.limit
          OR OLD.window_seconds IS DISTINCT FROM NEW.window_seconds
          OR OLD.expires_at IS DISTINCT FROM NEW.expires_at
          OR (OLD.settled_at IS NOT NULL AND OLD.settled_at IS DISTINCT FROM NEW.settled_at)
          OR OLD.created_at IS DISTINCT FROM NEW.created_at THEN
          RAISE EXCEPTION 'sensitive action reservation contract is immutable';
        END IF;
        IF OLD.status <> NEW.status AND NOT (
          OLD.status = 'pending' AND NEW.status IN ('succeeded', 'failed')
        ) THEN
          RAISE EXCEPTION 'invalid sensitive action reservation transition';
        END IF;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;

      CREATE TRIGGER sensitive_action_rate_limit_reservations_immutable
      BEFORE UPDATE ON sensitive_action_rate_limit_reservations
      FOR EACH ROW EXECUTE FUNCTION sensitive_action_rate_limit_reservations_immutable_fn();
    SQL
  end

  def extend_recovery_resolution_lifecycle
    add_column :minecraft_world_restore_resolutions, :expires_at, :datetime
    execute <<~SQL
      UPDATE minecraft_world_restore_resolutions
      SET expires_at = created_at + INTERVAL '10 minutes'
      WHERE expires_at IS NULL
    SQL
    change_column_null :minecraft_world_restore_resolutions, :expires_at, false
    add_column :minecraft_world_restore_resolutions, :expired_at, :datetime
    add_column :minecraft_world_restore_resolutions, :lifecycle_action, :string
    add_reference :minecraft_world_restore_resolutions,
      :lifecycle_actor,
      foreign_key: { to_table: :users }
    add_column :minecraft_world_restore_resolutions, :lifecycle_reason, :text
    add_column :minecraft_world_restore_resolutions, :lifecycle_request_id, :string, limit: 36
    add_column :minecraft_world_restore_resolutions, :lifecycle_request_digest, :string, limit: 64
    add_column :minecraft_world_restore_resolutions, :lifecycle_authorization_method, :string
    add_column :minecraft_world_restore_resolutions, :lifecycle_authorized_at, :datetime
    add_column :minecraft_world_restore_resolutions, :lifecycle_completed_at, :datetime
    add_column :minecraft_world_restore_resolutions, :supersedes_resolution_id, :bigint
    add_foreign_key :minecraft_world_restore_resolutions,
      :minecraft_world_restore_resolutions,
      column: :supersedes_resolution_id
    add_index :minecraft_world_restore_resolutions,
      :expires_at,
      name: "idx_minecraft_restore_resolutions_expires"
    add_index :minecraft_world_restore_resolutions,
      :lifecycle_request_id,
      unique: true,
      where: "lifecycle_request_id IS NOT NULL",
      name: "idx_minecraft_restore_resolutions_lifecycle_request"
    add_index :minecraft_world_restore_resolutions,
      :supersedes_resolution_id,
      unique: true,
      where: "supersedes_resolution_id IS NOT NULL",
      name: "idx_minecraft_restore_resolutions_supersedes"
    remove_check_constraint :minecraft_world_restore_resolutions,
      name: "chk_minecraft_restore_resolutions_status"
    add_check_constraint :minecraft_world_restore_resolutions,
      "status IN (#{quoted(NEW_RESOLUTION_STATUSES)})",
      name: "chk_minecraft_restore_resolutions_status"
    add_check_constraint :minecraft_world_restore_resolutions,
      "expires_at > created_at",
      name: "chk_minecraft_restore_resolutions_expires"
    add_check_constraint :minecraft_world_restore_resolutions, <<~SQL.squish,
      (
        status IN ('cancelled', 'taken_over')
        AND lifecycle_action = CASE status WHEN 'cancelled' THEN 'cancel' ELSE 'takeover' END
        AND lifecycle_actor_id IS NOT NULL
        AND char_length(lifecycle_reason) BETWEEN 1 AND 1000
        AND lifecycle_request_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND lifecycle_request_digest ~ '^[0-9a-f]{64}$'
        AND lifecycle_authorization_method IN ('password', 'totp', 'recovery_code')
        AND lifecycle_authorized_at IS NOT NULL
        AND lifecycle_completed_at IS NOT NULL
        AND expired_at IS NULL
      ) OR (
        status = 'expired'
        AND expired_at IS NOT NULL
        AND lifecycle_action IS NULL
        AND lifecycle_actor_id IS NULL
        AND lifecycle_reason IS NULL
        AND lifecycle_request_id IS NULL
        AND lifecycle_request_digest IS NULL
        AND lifecycle_authorization_method IS NULL
        AND lifecycle_authorized_at IS NULL
        AND lifecycle_completed_at IS NULL
      ) OR (
        status NOT IN ('expired', 'cancelled', 'taken_over')
        AND expired_at IS NULL
        AND lifecycle_action IS NULL
        AND lifecycle_actor_id IS NULL
        AND lifecycle_reason IS NULL
        AND lifecycle_request_id IS NULL
        AND lifecycle_request_digest IS NULL
        AND lifecycle_authorization_method IS NULL
        AND lifecycle_authorized_at IS NULL
        AND lifecycle_completed_at IS NULL
      )
    SQL
      name: "chk_minecraft_restore_resolutions_lifecycle"
  end

  def replace_resolution_trigger(statuses)
    execute "DROP TRIGGER IF EXISTS minecraft_world_restore_resolutions_immutable ON minecraft_world_restore_resolutions"
    extended = statuses.include?("taken_over")
    lifecycle_guard = if extended
      <<~SQL.squish
        OR OLD.expires_at IS DISTINCT FROM NEW.expires_at
        OR OLD.supersedes_resolution_id IS DISTINCT FROM NEW.supersedes_resolution_id
        OR (OLD.expired_at IS NOT NULL AND OLD.expired_at IS DISTINCT FROM NEW.expired_at)
        OR (OLD.lifecycle_action IS NOT NULL AND OLD.lifecycle_action IS DISTINCT FROM NEW.lifecycle_action)
        OR (OLD.lifecycle_actor_id IS NOT NULL AND OLD.lifecycle_actor_id IS DISTINCT FROM NEW.lifecycle_actor_id)
        OR (OLD.lifecycle_reason IS NOT NULL AND OLD.lifecycle_reason IS DISTINCT FROM NEW.lifecycle_reason)
        OR (OLD.lifecycle_request_id IS NOT NULL AND OLD.lifecycle_request_id IS DISTINCT FROM NEW.lifecycle_request_id)
        OR (OLD.lifecycle_request_digest IS NOT NULL AND OLD.lifecycle_request_digest IS DISTINCT FROM NEW.lifecycle_request_digest)
        OR (OLD.lifecycle_authorization_method IS NOT NULL AND OLD.lifecycle_authorization_method IS DISTINCT FROM NEW.lifecycle_authorization_method)
        OR (OLD.lifecycle_authorized_at IS NOT NULL AND OLD.lifecycle_authorized_at IS DISTINCT FROM NEW.lifecycle_authorized_at)
        OR (OLD.lifecycle_completed_at IS NOT NULL AND OLD.lifecycle_completed_at IS DISTINCT FROM NEW.lifecycle_completed_at)
      SQL
    else
      ""
    end
    lifecycle_transitions = extended ? <<~SQL.squish : ""
      OR (OLD.status IN ('planned', 'authorized') AND NEW.status IN ('expired', 'cancelled', 'taken_over'))
    SQL
    terminal_guard = if extended
      <<~SQL.squish
        IF (OLD.status IN ('completed', 'failed', 'recovery_required', 'expired', 'cancelled', 'taken_over')
            OR NEW.status IN ('completed', 'failed', 'recovery_required', 'expired', 'cancelled', 'taken_over'))
          AND (OLD.authorization_digest IS DISTINCT FROM NEW.authorization_digest
            OR OLD.authorization_method IS DISTINCT FROM NEW.authorization_method
            OR OLD.authorization_expires_at IS DISTINCT FROM NEW.authorization_expires_at
            OR OLD.authorized_at IS DISTINCT FROM NEW.authorized_at
            OR OLD.authorization_consumed_at IS DISTINCT FROM NEW.authorization_consumed_at) THEN
          RAISE EXCEPTION 'terminal recovery resolution authorization is immutable';
        END IF;
        IF OLD.status IN ('completed', 'failed', 'recovery_required', 'expired', 'cancelled', 'taken_over')
          AND (OLD.result_summary IS DISTINCT FROM NEW.result_summary
            OR OLD.error_code IS DISTINCT FROM NEW.error_code
            OR OLD.started_at IS DISTINCT FROM NEW.started_at
            OR OLD.completed_at IS DISTINCT FROM NEW.completed_at
            OR OLD.queued_at IS DISTINCT FROM NEW.queued_at
            OR OLD.minecraft_node_operation_id IS DISTINCT FROM NEW.minecraft_node_operation_id) THEN
          RAISE EXCEPTION 'terminal recovery resolution evidence is immutable';
        END IF;
      SQL
    else
      ""
    end

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
          OR OLD.pre_restore_manifest_digest IS DISTINCT FROM NEW.pre_restore_manifest_digest
          #{lifecycle_guard} THEN
          RAISE EXCEPTION 'minecraft world restore resolution contract is immutable';
        END IF;
        IF OLD.minecraft_node_operation_id IS NOT NULL
          AND OLD.minecraft_node_operation_id IS DISTINCT FROM NEW.minecraft_node_operation_id THEN
          RAISE EXCEPTION 'minecraft world restore resolution operation binding is immutable';
        END IF;
        #{terminal_guard}
        IF OLD.status IS DISTINCT FROM NEW.status AND NOT (
          (OLD.status = 'planned' AND NEW.status IN ('authorized', 'failed'))
          OR (OLD.status = 'authorized' AND NEW.status IN ('queued', 'failed'))
          OR (OLD.status IN ('queued', 'running')
            AND NEW.status IN ('running', 'completed', 'failed', 'recovery_required'))
          #{lifecycle_transitions}
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

  def drop_sensitive_action_reservations
    execute "DROP TRIGGER IF EXISTS sensitive_action_rate_limit_reservations_immutable ON sensitive_action_rate_limit_reservations"
    execute "DROP FUNCTION IF EXISTS sensitive_action_rate_limit_reservations_immutable_fn()"
    drop_table :sensitive_action_rate_limit_reservations
  end

  def quoted(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end
end
