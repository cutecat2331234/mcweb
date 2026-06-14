class CreateIdentityAndAdministration < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :public_id, null: false
      t.string :email, null: false
      t.string :username, null: false
      t.string :password_digest, null: false
      t.string :display_name
      t.boolean :email_verified, null: false, default: false
      t.datetime :email_verified_at
      t.string :email_verification_token_digest
      t.datetime :email_verification_sent_at
      t.string :password_reset_token_digest
      t.datetime :password_reset_sent_at
      t.string :totp_secret_ciphertext
      t.boolean :totp_enabled, null: false, default: false
      t.text :recovery_codes_ciphertext
      t.boolean :require_totp, null: false, default: false
      t.string :locale, null: false, default: "zh-CN"
      t.string :time_zone, null: false, default: "Asia/Shanghai"
      t.string :status, null: false, default: "active"
      t.datetime :banned_at
      t.datetime :ban_expires_at
      t.text :ban_reason
      t.datetime :deleted_at
      t.datetime :last_sign_in_at
      t.string :last_sign_in_ip
      t.integer :failed_login_count, null: false, default: 0
      t.datetime :locked_until
      t.timestamps
    end
    add_index :users, :public_id, unique: true
    add_index :users, :email, unique: true
    add_index :users, :username, unique: true
    add_index :users, :status
    add_index :users, :deleted_at

    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :ip_address
      t.text :user_agent
      t.boolean :remember_me, null: false, default: false
      t.datetime :last_active_at
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :sessions, :token_digest, unique: true
    add_index :sessions, :expires_at

    create_table :roles do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :system_role, null: false, default: false
      t.timestamps
    end
    add_index :roles, :key, unique: true

    create_table :permissions do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :category, null: false
      t.text :description
      t.timestamps
    end
    add_index :permissions, :key, unique: true

    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: true
      t.references :permission, null: false, foreign_key: true
      t.timestamps
    end
    add_index :role_permissions, [ :role_id, :permission_id ], unique: true

    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.timestamps
    end
    add_index :user_roles, [ :user_id, :role_id ], unique: true

    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :resource_type
      t.bigint :resource_id
      t.string :resource_public_id
      t.jsonb :metadata, null: false, default: {}
      t.jsonb :before_state, null: false, default: {}
      t.jsonb :after_state, null: false, default: {}
      t.string :ip_address
      t.text :user_agent
      t.text :reason
      t.timestamps
    end
    add_index :audit_logs, [ :resource_type, :resource_id ]
    add_index :audit_logs, :action
    add_index :audit_logs, :created_at

    create_table :site_settings do |t|
      t.string :key, null: false
      t.jsonb :value, null: false, default: {}
      t.timestamps
    end
    add_index :site_settings, :key, unique: true

    create_table :installation_locks do |t|
      t.boolean :locked, null: false, default: false
      t.datetime :locked_at
      t.references :locked_by, foreign_key: { to_table: :users }
      t.timestamps
    end

    create_table :rate_limit_counters do |t|
      t.string :key, null: false
      t.integer :count, null: false, default: 0
      t.datetime :window_start, null: false
      t.timestamps
    end
    add_index :rate_limit_counters, :key, unique: true
  end
end
