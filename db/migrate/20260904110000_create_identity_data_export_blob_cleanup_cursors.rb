# frozen_string_literal: true

class CreateIdentityDataExportBlobCleanupCursors < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_data_export_blob_cleanup_cursors do |t|
      t.string :name, null: false
      t.bigint :last_blob_id, null: false, default: 0
      t.bigint :cycle_max_blob_id, null: false, default: 0
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :name,
        unique: true,
        name: "idx_identity_export_blob_cleanup_cursor_name"
      t.check_constraint "last_blob_id >= 0",
        name: "chk_identity_export_cleanup_last_blob_id"
      t.check_constraint "cycle_max_blob_id >= 0",
        name: "chk_identity_export_cleanup_cycle_max_blob_id"
      t.check_constraint(
        "(last_blob_id = 0 AND cycle_max_blob_id = 0) OR " \
          "(cycle_max_blob_id > 0 AND last_blob_id <= cycle_max_blob_id)",
        name: "chk_identity_export_cleanup_cursor_bounds"
      )
    end
  end
end
