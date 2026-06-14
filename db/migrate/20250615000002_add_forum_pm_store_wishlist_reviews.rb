# frozen_string_literal: true

class AddForumPmStoreWishlistReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_conversations do |t|
      t.datetime :last_message_at
      t.timestamps
    end

    create_table :forum_conversation_participants do |t|
      t.references :forum_conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_read_at
      t.timestamps
    end
    add_index :forum_conversation_participants, [ :forum_conversation_id, :user_id ], unique: true, name: "idx_forum_conv_participants_unique"

    create_table :forum_messages do |t|
      t.references :forum_conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_index :forum_messages, [ :forum_conversation_id, :created_at ]

    create_table :store_wishlist_items do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.timestamps
    end
    add_index :store_wishlist_items, [ :user_id, :store_product_id ], unique: true

    create_table :store_reviews do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.integer :rating, null: false
      t.text :body
      t.string :status, null: false, default: "published"
      t.timestamps
    end
    add_index :store_reviews, [ :store_product_id, :user_id ], unique: true
    add_index :store_reviews, [ :store_product_id, :status ]
  end
end
