# frozen_string_literal: true

class CreateForumUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_uploads do |t|
      t.references :user, null: false, foreign_key: true
      t.references :active_storage_blob,
        null: true,
        foreign_key: { to_table: :active_storage_blobs, on_delete: :nullify },
        index: { unique: true }
      t.references :forum_post_attachment,
        null: true,
        foreign_key: { to_table: :forum_post_attachments, on_delete: :nullify },
        index: { unique: true }
      t.references :forum_post,
        null: true,
        foreign_key: { to_table: :forum_posts, on_delete: :nullify }
      t.string :public_id, null: false
      t.string :kind, null: false
      t.string :status, null: false, default: "reserved"
      t.bigint :byte_size, null: false
      t.datetime :expires_at
      t.datetime :cleanup_started_at
      t.datetime :cleaned_at
      t.integer :cleanup_attempts, null: false, default: 0
      t.string :cleanup_error_code
      t.text :cleanup_error_message
      t.timestamps
    end

    add_index :forum_uploads, :public_id, unique: true
    add_index :forum_uploads, %i[status expires_at]
    add_index :forum_uploads, %i[user_id status]
    add_index :forum_uploads, %i[kind status]
    add_check_constraint :forum_uploads,
      "byte_size > 0",
      name: "forum_uploads_positive_byte_size"
    add_check_constraint :forum_uploads,
      "kind IN ('inline_image', 'post_attachment')",
      name: "forum_uploads_valid_kind"
    add_check_constraint :forum_uploads,
      "status IN ('reserved', 'stored', 'linked', 'cleanup_pending', 'cleanup_failed', 'cleaned')",
      name: "forum_uploads_valid_status"
  end
end
