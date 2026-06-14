# frozen_string_literal: true

class AddRound14Features < ActiveRecord::Migration[8.0]
  def change
    create_table :active_storage_blobs do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum
      t.datetime :created_at,   null: false
    end
    add_index :active_storage_blobs, :key, unique: true

    create_table :active_storage_attachments do |t|
      t.string     :name,     null: false
      t.references :record,   null: false, polymorphic: true, index: false
      t.references :blob,     null: false
      t.datetime   :created_at, null: false
    end
    add_index :active_storage_attachments,
              %i[record_type record_id name blob_id],
              name: "index_active_storage_attachments_uniqueness", unique: true

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false
      t.index %i[blob_id variation_digest],
              name: "index_active_storage_variant_records_uniqueness", unique: true
    end

    add_column :forum_topics, :scheduled_at, :datetime
    add_index :forum_topics, :scheduled_at

    create_table :forum_badges do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :icon, default: "🏅", null: false
      t.string :color, default: "#6366f1"
      t.string :grant_rule, default: "manual", null: false
      t.integer :grant_threshold, default: 0
      t.timestamps
    end
    add_index :forum_badges, :slug, unique: true

    create_table :forum_user_badges do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_badge, null: false, foreign_key: true
      t.datetime :granted_at, null: false
      t.timestamps
    end
    add_index :forum_user_badges, %i[user_id forum_badge_id], unique: true

    create_table :ip_bans do |t|
      t.string :ip_address, null: false
      t.text :reason
      t.references :banned_by, foreign_key: { to_table: :users }
      t.datetime :expires_at
      t.timestamps
    end
    add_index :ip_bans, :ip_address, unique: true

    create_table :store_product_questions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.text :body, null: false
      t.string :status, default: "published", null: false
      t.timestamps
    end

    create_table :store_product_answers do |t|
      t.references :store_product_question, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.boolean :official, default: false, null: false
      t.timestamps
    end

    add_column :users, :wishlist_share_token, :string
    add_index :users, :wishlist_share_token, unique: true
  end
end
