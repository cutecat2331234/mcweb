# frozen_string_literal: true

class AddMembershipAndPrerequisites < ActiveRecord::Migration[8.0]
  def change
    create_table :store_membership_types do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description
      t.string :color
      t.string :icon
      t.string :duration_mode, null: false, default: "fixed_days"
      t.integer :duration_days
      t.string :luckperms_group
      t.boolean :game_permission_enabled, null: false, default: true
      t.string :game_permission_mode, null: false, default: "website_managed"
      t.jsonb :grant_commands, null: false, default: []
      t.jsonb :revoke_commands, null: false, default: []
      t.integer :display_priority, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :store_membership_types, :slug, unique: true
    add_index :store_membership_types, :active

    create_table :store_user_memberships do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_membership_type, null: false, foreign_key: true
      t.string :status, null: false, default: "active"
      t.datetime :starts_at, null: false
      t.datetime :expires_at
      t.string :source, null: false, default: "purchase"
      t.bigint :source_order_item_id
      t.timestamps
    end
    add_index :store_user_memberships, %i[user_id store_membership_type_id status],
              name: "idx_user_memberships_user_type_status"
    add_index :store_user_memberships, :expires_at
    add_index :store_user_memberships, :source_order_item_id, unique: true, where: "source_order_item_id IS NOT NULL",
              name: "idx_user_memberships_source_order_item_unique"
    add_foreign_key :store_user_memberships, :store_order_items, column: :source_order_item_id

    create_table :store_product_prerequisites do |t|
      t.references :store_product, null: false, foreign_key: true
      t.references :required_product, null: false, foreign_key: { to_table: :store_products }
      t.string :requirement_mode, null: false, default: "ever_purchased"
      t.timestamps
    end
    add_index :store_product_prerequisites, %i[store_product_id required_product_id],
              unique: true, name: "idx_product_prerequisites_unique"

    create_table :store_user_entitlements do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_product, null: false, foreign_key: true
      t.bigint :source_order_item_id
      t.datetime :starts_at, null: false
      t.datetime :expires_at
      t.timestamps
    end
    add_index :store_user_entitlements, %i[user_id store_product_id]
    add_index :store_user_entitlements, :expires_at
    add_index :store_user_entitlements, :source_order_item_id, unique: true, where: "source_order_item_id IS NOT NULL",
              name: "idx_user_entitlements_source_order_item_unique"
    add_foreign_key :store_user_entitlements, :store_order_items, column: :source_order_item_id

    add_reference :store_products, :store_membership_type, foreign_key: true
    add_column :store_products, :prerequisite_match_mode, :string, null: false, default: "all"
  end
end
