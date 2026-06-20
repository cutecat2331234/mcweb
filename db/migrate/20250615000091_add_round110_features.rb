# frozen_string_literal: true

class AddRound110Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_post_attachments do |t|
      t.references :forum_post, null: true, foreign_key: { to_table: :forum_posts }
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :content_type
      t.bigint :byte_size, null: false, default: 0
      t.integer :download_count, null: false, default: 0
      t.timestamps
    end

    add_index :forum_post_attachments, %i[user_id forum_post_id]
  end
end
