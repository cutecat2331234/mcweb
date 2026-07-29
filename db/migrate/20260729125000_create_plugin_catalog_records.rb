# frozen_string_literal: true

class CreatePluginCatalogRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :plugin_releases do |t|
      t.references :plugin_installation,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :plugin_id, null: false
      t.string :version, null: false
      t.string :api_version, null: false
      t.string :state, null: false
      t.jsonb :manifest_descriptor, null: false, default: {}
      t.string :manifest_sha256, null: false
      t.string :package_sha256, null: false
      t.string :package_digest_source, null: false
      t.string :operation_id
      t.string :health, null: false, default: "untracked"
      t.jsonb :diagnostics, null: false, default: []
      t.datetime :observed_at, null: false
      t.timestamps
    end

    add_index :plugin_releases,
              [ :plugin_installation_id, :version, :package_sha256 ],
              unique: true,
              name: "idx_plugin_releases_identity"
    add_index :plugin_releases, [ :plugin_id, :state ]
    add_index :plugin_releases, [ :health, :observed_at ]
    add_index :plugin_releases,
              :plugin_installation_id,
              unique: true,
              where: "state IN ('active', 'disabled', 'uninstalled')",
              name: "idx_plugin_releases_current"
    add_check_constraint :plugin_releases,
                         "state IN ('active', 'disabled', 'rollback', 'uninstalled')",
                         name: "plugin_releases_state"
    add_check_constraint :plugin_releases,
                         "package_digest_source IN ('receipt', 'derived')",
                         name: "plugin_releases_digest_source"
    add_check_constraint :plugin_releases,
                         "health IN ('healthy', 'changed', 'missing', 'unavailable', 'untracked')",
                         name: "plugin_releases_health"

    create_table :plugin_contributions do |t|
      t.references :plugin_release,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :contribution_id, null: false
      t.string :contribution_type, null: false
      t.jsonb :descriptor, null: false, default: {}
      t.string :descriptor_sha256, null: false
      t.string :schema_sha256
      t.timestamps
    end

    add_index :plugin_contributions,
              [ :plugin_release_id, :contribution_id ],
              unique: true,
              name: "idx_plugin_contributions_release_id"
    add_index :plugin_contributions, [ :contribution_type, :contribution_id ]

    create_table :plugin_files do |t|
      t.references :plugin_release,
                   null: false,
                   foreign_key: { on_delete: :cascade }
      t.string :path, null: false
      t.bigint :byte_size, null: false
      t.string :sha256, null: false
      t.boolean :expected, null: false, default: true
      t.bigint :observed_byte_size
      t.string :observed_sha256
      t.string :health, null: false
      t.timestamps
    end

    add_index :plugin_files,
              [ :plugin_release_id, :path ],
              unique: true,
              name: "idx_plugin_files_release_path"
    add_index :plugin_files, [ :health, :updated_at ]
    add_check_constraint :plugin_files,
                         "byte_size >= 0 AND (observed_byte_size IS NULL OR observed_byte_size >= 0)",
                         name: "plugin_files_nonnegative_sizes"
    add_check_constraint :plugin_files,
                         "health IN ('healthy', 'missing', 'modified', 'unknown', 'unavailable', 'untracked')",
                         name: "plugin_files_health"
  end
end
