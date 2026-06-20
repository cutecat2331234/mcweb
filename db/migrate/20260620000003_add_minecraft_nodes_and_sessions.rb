# frozen_string_literal: true

class AddMinecraftNodesAndSessions < ActiveRecord::Migration[8.0]
  def change
    create_table :minecraft_nodes do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :hostname
      t.text :encrypted_node_secret
      t.string :node_secret_fingerprint
      t.string :status, null: false, default: "offline"
      t.datetime :last_heartbeat_at
      t.jsonb :metadata, null: false, default: {}
      t.string :proxy_listen_url, default: "http://127.0.0.1:9876"
      t.timestamps
    end
    add_index :minecraft_nodes, :public_id, unique: true

    change_table :minecraft_servers, bulk: true do |t|
      t.references :minecraft_node, foreign_key: true, index: true
      t.string :connection_mode, null: false, default: "direct"
      t.string :proxy_listen_url
      t.string :process_driver
      t.jsonb :process_config, null: false, default: {}
      t.string :process_state, null: false, default: "stopped"
      t.string :working_directory
    end

    create_table :minecraft_node_tasks do |t|
      t.references :minecraft_node, null: false, foreign_key: true
      t.references :minecraft_server, foreign_key: true
      t.string :task_type, null: false
      t.string :delivery_id
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :claimed_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :minecraft_node_tasks, :delivery_id, unique: true, where: "delivery_id IS NOT NULL"
    add_index :minecraft_node_tasks, %i[minecraft_node_id status]

    create_table :minecraft_player_sessions do |t|
      t.references :player_profile, null: false, foreign_key: { to_table: :minecraft_player_profiles }
      t.references :minecraft_server, null: false, foreign_key: true
      t.string :username, null: false
      t.datetime :joined_at, null: false
      t.datetime :ended_at
      t.string :source, null: false, default: "connector"
      t.timestamps
    end
    add_index :minecraft_player_sessions, %i[player_profile_id ended_at]
    add_index :minecraft_player_sessions, %i[minecraft_server_id ended_at]
  end
end
