class CreateMinecraftAndNotifications < ActiveRecord::Migration[8.1]
  def change
    create_table :minecraft_servers do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :address
      t.integer :port, null: false, default: 25565
      t.string :status, null: false, default: "offline"
      t.integer :online_players, null: false, default: 0
      t.integer :max_players, null: false, default: 0
      t.string :version
      t.text :encrypted_connector_secret
      t.string :connector_secret_fingerprint
      t.datetime :last_heartbeat_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :minecraft_servers, :public_id, unique: true

    create_table :minecraft_identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :uuid, null: false
      t.string :username, null: false
      t.string :identity_type, null: false, default: "java"
      t.references :minecraft_server, foreign_key: true
      t.datetime :linked_at, null: false
      t.timestamps
    end
    add_index :minecraft_identities, [ :uuid, :identity_type ], unique: true

    create_table :minecraft_link_codes do |t|
      t.references :minecraft_server, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.string :minecraft_uuid, null: false
      t.string :minecraft_username, null: false
      t.string :identity_type, null: false, default: "java"
      t.datetime :expires_at, null: false
      t.datetime :used_at
      t.references :used_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :minecraft_link_codes, :code_digest, unique: true

    create_table :minecraft_connector_tasks do |t|
      t.references :minecraft_server, null: false, foreign_key: true
      t.references :store_fulfillment, foreign_key: true
      t.string :task_type, null: false
      t.string :delivery_id
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :claimed_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :minecraft_connector_tasks, :delivery_id, unique: true, where: "delivery_id IS NOT NULL"

    create_table :minecraft_processed_deliveries do |t|
      t.references :minecraft_server, null: false, foreign_key: true
      t.string :delivery_id, null: false
      t.string :status, null: false
      t.jsonb :result, null: false, default: {}
      t.timestamps
    end
    add_index :minecraft_processed_deliveries, [ :minecraft_server_id, :delivery_id ], unique: true

    create_table :notifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :notification_type, null: false
      t.string :title, null: false
      t.text :body
      t.jsonb :metadata, null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end
    add_index :notifications, [ :user_id, :read_at ]

    create_table :notification_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :notification_type, null: false
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    add_index :notification_preferences, [ :user_id, :channel, :notification_type ], unique: true
  end
end
