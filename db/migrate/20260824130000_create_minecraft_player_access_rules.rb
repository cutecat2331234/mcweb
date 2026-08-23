# frozen_string_literal: true

class CreateMinecraftPlayerAccessRules < ActiveRecord::Migration[8.1]
  def up
    create_table :minecraft_player_access_rules do |table|
      table.string :public_id, null: false
      table.references :minecraft_server,
                       null: false,
                       foreign_key: true,
                       index: { name: "idx_mc_access_rules_server" }
      table.string :rule_type, null: false
      table.string :status, null: false, default: "pending_apply"
      table.string :username, null: false, limit: 16
      table.uuid :player_uuid
      table.text :reason, null: false
      table.datetime :expires_at
      table.references :created_by,
                       null: true,
                       foreign_key: { to_table: :users }
      table.references :revoked_by,
                       null: true,
                       foreign_key: { to_table: :users }
      table.text :revoke_reason
      table.references :apply_task,
                       null: true,
                       foreign_key: { to_table: :minecraft_connector_tasks }
      table.references :revoke_task,
                       null: true,
                       foreign_key: { to_table: :minecraft_connector_tasks }
      table.string :apply_idempotency_key_digest, null: false, limit: 64
      table.string :revoke_idempotency_key_digest, limit: 64
      table.datetime :applied_at
      table.datetime :revoked_at
      table.datetime :failed_at
      table.integer :lock_version, null: false, default: 0
      table.timestamps
    end

    add_index :minecraft_player_access_rules, :public_id,
              unique: true,
              name: "idx_mc_access_rules_public_id"
    add_index :minecraft_player_access_rules, :apply_idempotency_key_digest,
              unique: true,
              name: "idx_mc_access_rules_apply_idempotency"
    add_index :minecraft_player_access_rules, :revoke_idempotency_key_digest,
              unique: true,
              where: "revoke_idempotency_key_digest IS NOT NULL",
              name: "idx_mc_access_rules_revoke_idempotency"
    add_index :minecraft_player_access_rules, [ :status, :expires_at, :id ],
              name: "idx_mc_access_rules_expiry"
    execute <<~SQL
      CREATE UNIQUE INDEX idx_mc_access_rules_active_target
      ON minecraft_player_access_rules (minecraft_server_id, rule_type, lower(username))
      WHERE status IN ('pending_apply', 'active', 'pending_revoke')
    SQL

    add_check_constraint :minecraft_player_access_rules,
                         "rule_type IN ('whitelist', 'ban')",
                         name: "mc_access_rules_type"
    add_check_constraint :minecraft_player_access_rules,
                         "status IN ('pending_apply', 'active', 'pending_revoke', 'revoked', 'failed')",
                         name: "mc_access_rules_status"
    add_check_constraint :minecraft_player_access_rules,
                         "char_length(btrim(reason)) BETWEEN 1 AND 500",
                         name: "mc_access_rules_reason_length"
    add_check_constraint :minecraft_player_access_rules,
                         "revoke_reason IS NULL OR char_length(btrim(revoke_reason)) BETWEEN 1 AND 500",
                         name: "mc_access_rules_revoke_reason_length"
    add_check_constraint :minecraft_player_access_rules,
                         "lock_version >= 0",
                         name: "mc_access_rules_lock_version"
  end

  def down
    drop_table :minecraft_player_access_rules
  end
end
