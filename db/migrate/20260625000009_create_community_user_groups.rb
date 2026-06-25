# frozen_string_literal: true

class CreateCommunityUserGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :community_user_groups do |t|
      t.string :name, null: false
      t.string :color_hex
      t.integer :priority, null: false, default: 0
      t.jsonb :permissions, null: false, default: []
      t.boolean :is_primary_default, null: false, default: false
      t.string :banner_text
      t.timestamps
    end

    create_table :community_group_memberships do |t|
      t.bigint :user_id, null: false
      t.bigint :community_user_group_id, null: false
      t.boolean :is_primary, null: false, default: false
      t.timestamps
    end

    add_index :community_group_memberships, [ :user_id, :community_user_group_id ],
              unique: true, name: "idx_community_group_memberships_unique"
    add_index :community_group_memberships, :community_user_group_id,
              name: "idx_community_group_memberships_on_group"
    add_foreign_key :community_group_memberships, :users
    add_foreign_key :community_group_memberships, :community_user_groups
  end
end
