# frozen_string_literal: true

class AddRound40Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :color_hex, :string
    add_column :forum_sections, :icon, :string

    create_table :forum_topic_invites do |t|
      t.references :forum_topic, null: false, foreign_key: { to_table: :forum_topics }
      t.references :user, null: false, foreign_key: true
      t.references :invited_by, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :forum_topic_invites, [ :forum_topic_id, :user_id ], unique: true

    add_column :forum_posts, :post_type, :string, default: "regular", null: false
    add_column :forum_posts, :wiki, :boolean, default: false, null: false

    add_reference :store_gift_cards, :source_order_item, foreign_key: { to_table: :store_order_items }
  end
end
