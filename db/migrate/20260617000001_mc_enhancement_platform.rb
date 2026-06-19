# frozen_string_literal: true

class McEnhancementPlatform < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :account_type, :string, default: "member", null: false
    add_index :users, :account_type

    create_table :admin_module_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.string :module_key, null: false
      t.references :granted_by, foreign_key: { to_table: :users }
      t.datetime :granted_at, null: false
      t.timestamps
    end
    add_index :admin_module_grants, %i[user_id module_key], unique: true

    create_table :minecraft_player_profiles do |t|
      t.string :public_id, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :minecraft_player_profiles, :public_id, unique: true

    create_table :minecraft_player_identities do |t|
      t.references :player_profile, null: false, foreign_key: { to_table: :minecraft_player_profiles }
      t.string :platform, default: "java", null: false
      t.string :external_uuid, null: false
      t.string :username, null: false
      t.string :identity_type, default: "java", null: false
      t.datetime :valid_from, null: false
      t.datetime :superseded_at
      t.string :skin_texture_url
      t.string :skin_model
      t.string :cape_texture_url
      t.datetime :last_seen_ingame_at
      t.references :primary_server, foreign_key: { to_table: :minecraft_servers }
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :minecraft_player_identities, %i[platform external_uuid], unique: true, where: "superseded_at IS NULL"
    add_index :minecraft_player_identities, :username

    create_table :minecraft_identity_links do |t|
      t.references :player_profile, null: false, foreign_key: { to_table: :minecraft_player_profiles }
      t.references :user, null: false, foreign_key: true
      t.datetime :linked_at, null: false
      t.datetime :unlinked_at
      t.timestamps
    end
    add_index :minecraft_identity_links, %i[player_profile_id user_id], unique: true, where: "unlinked_at IS NULL"

    add_reference :minecraft_identities, :player_profile, foreign_key: { to_table: :minecraft_player_profiles }

    add_column :minecraft_identities, :skin_texture_url, :string
    add_column :minecraft_identities, :skin_model, :string
    add_column :minecraft_identities, :cape_texture_url, :string
    add_column :minecraft_identities, :last_seen_ingame_at, :datetime
    add_column :minecraft_identities, :metadata, :jsonb, default: {}, null: false

    create_table :minecraft_permission_groups do |t|
      t.references :player_profile, null: false, foreign_key: { to_table: :minecraft_player_profiles }
      t.string :group_key, null: false
      t.string :group_label
      t.integer :weight, default: 0, null: false
      t.string :source, default: "manual", null: false
      t.datetime :synced_at
      t.timestamps
    end
    add_index :minecraft_permission_groups, %i[player_profile_id group_key], unique: true

    create_table :minecraft_profile_field_definitions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :field_type, default: "text", null: false
      t.string :icon
      t.integer :sort_order, default: 0, null: false
      t.string :visibility, default: "public", null: false
      t.string :source, default: "plugin", null: false
      t.string :group_name
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :minecraft_profile_field_definitions, :key, unique: true

    create_table :minecraft_profile_field_values do |t|
      t.references :player_profile, null: false, foreign_key: { to_table: :minecraft_player_profiles }
      t.string :field_key, null: false
      t.text :value
      t.string :updated_by, default: "plugin", null: false
      t.timestamps
    end
    add_index :minecraft_profile_field_values, %i[player_profile_id field_key], unique: true

    create_table :minecraft_integration_actions do |t|
      t.string :name, null: false
      t.string :event_key, null: false
      t.jsonb :conditions, default: {}, null: false
      t.jsonb :actions, default: [], null: false
      t.boolean :enabled, default: true, null: false
      t.integer :priority, default: 0, null: false
      t.timestamps
    end
    add_index :minecraft_integration_actions, :event_key

    create_table :minecraft_integration_action_logs do |t|
      t.references :integration_action, foreign_key: { to_table: :minecraft_integration_actions }
      t.string :event_id, null: false
      t.string :event_key, null: false
      t.jsonb :payload, default: {}, null: false
      t.string :status, default: "completed", null: false
      t.text :error_message
      t.timestamps
    end
    add_index :minecraft_integration_action_logs, :event_id, unique: true

    create_table :minecraft_server_snapshots do |t|
      t.references :minecraft_server, null: false, foreign_key: true
      t.integer :online_players, default: 0, null: false
      t.integer :max_players, default: 0, null: false
      t.float :tps
      t.bigint :memory_used_bytes
      t.bigint :memory_max_bytes
      t.string :motd
      t.string :version
      t.jsonb :plugins, default: [], null: false
      t.jsonb :worlds, default: [], null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end
    add_index :minecraft_server_snapshots, %i[minecraft_server_id created_at]
  end
end
