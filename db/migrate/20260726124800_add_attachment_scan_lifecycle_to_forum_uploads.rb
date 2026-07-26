# frozen_string_literal: true

class AddAttachmentScanLifecycleToForumUploads < ActiveRecord::Migration[8.1]
  def up
    change_table :forum_uploads, bulk: true do |t|
      t.string :scan_status, null: false, default: "pending"
      t.integer :scan_attempts, null: false, default: 0
      t.datetime :scan_started_at
      t.datetime :next_scan_at
      t.datetime :scanned_at
      t.datetime :quarantined_at
      t.string :scanner
      t.string :scan_result_code
      t.text :scan_error_message
    end

    execute <<~SQL.squish
      UPDATE forum_uploads
      SET
        scan_status = CASE
          WHEN kind = 'inline_image' THEN 'clean'
          ELSE 'pending'
        END,
        scanner = CASE
          WHEN kind = 'inline_image' THEN 'image_inspector'
          ELSE NULL
        END,
        scan_result_code = CASE
          WHEN kind = 'inline_image' THEN 'decoded_image'
          ELSE NULL
        END,
        scanned_at = CASE
          WHEN kind = 'inline_image' THEN CURRENT_TIMESTAMP
          ELSE NULL
        END,
        next_scan_at = CASE
          WHEN kind = 'post_attachment' THEN CURRENT_TIMESTAMP
          ELSE NULL
        END
    SQL

    add_index :forum_uploads, %i[scan_status next_scan_at],
      name: "idx_forum_uploads_scan_due"
    add_index :forum_uploads, :quarantined_at
    add_check_constraint :forum_uploads,
      "scan_status IN ('pending', 'clean', 'infected', 'error')",
      name: "forum_uploads_valid_scan_status"
    add_check_constraint :forum_uploads,
      "scan_attempts >= 0",
      name: "forum_uploads_nonnegative_scan_attempts"
  end

  def down
    remove_check_constraint :forum_uploads,
      name: "forum_uploads_nonnegative_scan_attempts"
    remove_check_constraint :forum_uploads,
      name: "forum_uploads_valid_scan_status"
    remove_index :forum_uploads, :quarantined_at
    remove_index :forum_uploads, name: "idx_forum_uploads_scan_due"
    remove_columns :forum_uploads,
      :scan_status,
      :scan_attempts,
      :scan_started_at,
      :next_scan_at,
      :scanned_at,
      :quarantined_at,
      :scanner,
      :scan_result_code,
      :scan_error_message
  end
end
