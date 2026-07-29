# frozen_string_literal: true

class CompleteDataGovernanceContentLifecycle < ActiveRecord::Migration[8.1]
  PERMISSIONS = {
    "data_governance.read" => [
      "View data governance",
      "View retention policies, retention holds, and governed-content lifecycle records"
    ],
    "data_governance.policies.manage" => [
      "Manage retention policies",
      "Change governed-content retention periods and deletion capabilities"
    ],
    "data_governance.holds.manage" => [
      "Manage retention holds",
      "Place and release audited retention holds on governed content"
    ],
    "data_governance.content.delete" => [
      "Soft-delete governed content",
      "Move governed content into its reversible retention period"
    ],
    "data_governance.content.restore" => [
      "Restore governed content",
      "Restore eligible governed content before permanent cleanup"
    ],
    "data_governance.content.purge" => [
      "Permanently purge governed content",
      "Permanently remove due content after all retention and evidence blockers clear"
    ]
  }.freeze

  LEGACY_GRANTS = {
    "data_governance.read" => "system.audit.read",
    "data_governance.policies.manage" => "system.settings.manage",
    "data_governance.holds.manage" => "system.settings.manage",
    "data_governance.content.delete" => "forum.topics.edit_others",
    "data_governance.content.restore" => "forum.topics.edit_others",
    "data_governance.content.purge" => "system.settings.manage"
  }.freeze

  def up
    add_column :forum_post_attachments, :deleted_at, :datetime
    add_index :forum_post_attachments, :deleted_at

    create_table :data_content_lifecycle_records do |t|
      t.string :public_id, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :status, null: false, default: "soft_deleted"
      t.references :deleted_by, foreign_key: { to_table: :users }
      t.references :restored_by, foreign_key: { to_table: :users }
      t.references :purged_by, foreign_key: { to_table: :users }
      t.datetime :soft_deleted_at, null: false
      t.datetime :purge_after
      t.datetime :restored_at
      t.datetime :purged_at
      t.text :deletion_reason, null: false
      t.text :restoration_reason
      t.text :purge_reason
      t.jsonb :target_snapshot, null: false, default: {}
      t.jsonb :blocker_codes, null: false, default: []
      t.datetime :last_evaluated_at
      t.integer :purge_attempts, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :public_id, unique: true
      t.index %i[target_type target_id], unique: true, name: "idx_data_lifecycle_target"
      t.index %i[status purge_after id], name: "idx_data_lifecycle_due"
      t.check_constraint(
        "status IN ('soft_deleted', 'restored', 'purged')",
        name: "chk_data_content_lifecycle_status"
      )
      t.check_constraint(
        "purge_attempts >= 0",
        name: "chk_data_content_lifecycle_attempts"
      )
    end

    PERMISSIONS.each do |key, (name, description)|
      execute <<~SQL.squish
        INSERT INTO permissions (key, name, category, description, created_at, updated_at)
        VALUES (
          #{connection.quote(key)},
          #{connection.quote(name)},
          'data_governance',
          #{connection.quote(description)},
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    LEGACY_GRANTS.each do |new_key, legacy_key|
      execute <<~SQL.squish
        INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
        SELECT role_permissions.role_id, new_permission.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM role_permissions
        INNER JOIN permissions legacy_permission
          ON legacy_permission.id = role_permissions.permission_id
        CROSS JOIN permissions new_permission
        WHERE legacy_permission.key = #{connection.quote(legacy_key)}
          AND new_permission.key = #{connection.quote(new_key)}
        ON CONFLICT (role_id, permission_id) DO NOTHING
      SQL
    end
  end

  def down
    quoted_keys = PERMISSIONS.keys.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key IN (#{quoted_keys}))
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions WHERE key IN (#{quoted_keys})
    SQL

    drop_table :data_content_lifecycle_records
    remove_index :forum_post_attachments, :deleted_at
    remove_column :forum_post_attachments, :deleted_at
  end
end
