# frozen_string_literal: true

class AddForumBlocksPollsDraftsAndProductImages < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_user_blocks do |t|
      t.references :blocker, null: false, foreign_key: { to_table: :users }
      t.references :blocked, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :forum_user_blocks, [ :blocker_id, :blocked_id ], unique: true

    create_table :forum_polls do |t|
      t.references :forum_topic, null: false, foreign_key: true, index: { unique: true }
      t.string :question, null: false
      t.jsonb :options, null: false, default: []
      t.datetime :closes_at
      t.timestamps
    end

    create_table :forum_poll_votes do |t|
      t.references :forum_poll, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :option_index, null: false
      t.timestamps
    end
    add_index :forum_poll_votes, [ :forum_poll_id, :user_id ], unique: true

    add_column :store_products, :image_url, :string
    add_column :store_refunds, :requested_by_customer, :boolean, default: false, null: false
  end
end
