# frozen_string_literal: true

class AddRound57Features < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_tag_groups do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :one_per_topic, default: false, null: false
      t.timestamps
    end
    add_index :forum_tag_groups, :slug, unique: true

    create_table :forum_tag_group_memberships do |t|
      t.references :forum_tag_group, null: false, foreign_key: true
      t.references :forum_tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :forum_tag_group_memberships, [ :forum_tag_group_id, :forum_tag_id ],
              unique: true, name: "idx_tag_group_membership_unique"

    add_column :forum_sections, :required_tag_group_ids, :jsonb, default: [], null: false

    add_column :forum_topics, :auto_archive_at, :datetime
    add_index :forum_topics, :auto_archive_at

    add_column :store_order_staff_notes, :visible_to_customer, :boolean, default: false, null: false

    add_column :users, :store_credit_cents, :integer, default: 0, null: false

    create_table :store_credit_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :store_order, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users }
      t.integer :amount_cents, null: false
      t.string :note
      t.timestamps
    end

    add_column :store_orders, :store_credit_amount_cents, :integer, default: 0, null: false

    add_column :store_products, :available_at, :datetime
    add_column :store_products, :unavailable_at, :datetime
    add_index :store_products, :available_at
    add_index :store_products, :unavailable_at
  end
end
