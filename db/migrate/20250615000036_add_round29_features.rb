# frozen_string_literal: true

class AddRound29Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_section_mutes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_section, null: false, foreign_key: true
      t.timestamps
    end
    add_index :forum_section_mutes, %i[user_id forum_section_id], unique: true

    create_table :forum_user_ignores do |t|
      t.references :ignorer, null: false, foreign_key: { to_table: :users }
      t.references :ignored, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :forum_user_ignores, %i[ignorer_id ignored_id], unique: true

    add_column :forum_topics, :lock_reason, :string
    add_column :store_products, :summary, :text

    create_table :store_price_alerts do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.references :store_product_variant, foreign_key: true
      t.integer :baseline_price_cents, null: false
      t.datetime :notified_at
      t.timestamps
    end
    add_index :store_price_alerts, %i[user_id store_product_id], unique: true
  end
end
