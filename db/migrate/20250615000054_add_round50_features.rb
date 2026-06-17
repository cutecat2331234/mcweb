# frozen_string_literal: true

class AddRound50Features < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_tags, :canonical_tag_id, :bigint
    add_index :forum_tags, :canonical_tag_id
    add_foreign_key :forum_tags, :forum_tags, column: :canonical_tag_id

    add_column :forum_topics, :auto_bump_at, :datetime
    add_index :forum_topics, :auto_bump_at

    add_column :users, :forum_flair_color_hex, :string
    add_column :users, :compare_share_token, :string
    add_column :users, :compare_product_ids, :jsonb, default: [], null: false
    add_index :users, :compare_share_token, unique: true

    create_table :store_order_staff_notes do |t|
      t.references :store_order, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end

    add_column :store_orders, :gift_wrap, :boolean, default: false, null: false
    add_column :store_orders, :gift_wrap_cents, :integer, default: 0, null: false
  end
end
