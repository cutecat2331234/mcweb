# frozen_string_literal: true

class AddRound20Features < ActiveRecord::Migration[8.1]
  def change
    change_table :forum_bookmarks, bulk: true do |t|
      t.text :note
      t.datetime :remind_at
    end
    add_index :forum_bookmarks, :remind_at, where: "remind_at IS NOT NULL"

    change_table :forum_polls, bulk: true do |t|
      t.boolean :multiple_choice, default: false, null: false
      t.integer :max_choices, default: 1, null: false
    end

    remove_index :forum_poll_votes, name: "index_forum_poll_votes_on_forum_poll_id_and_user_id"
    add_index :forum_poll_votes, %i[forum_poll_id user_id option_index],
              unique: true,
              name: "index_forum_poll_votes_on_poll_user_option"

    change_table :users, bulk: true do |t|
      t.text :forum_signature
      t.datetime :last_seen_at
    end
    add_index :users, :last_seen_at

    change_table :store_coupons, bulk: true do |t|
      t.jsonb :product_ids, default: [], null: false
      t.jsonb :category_ids, default: [], null: false
    end

    add_reference :store_wishlist_items, :variant,
                  foreign_key: { to_table: :store_product_variants },
                  index: true
  end
end
