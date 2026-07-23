# frozen_string_literal: true

class CreateApiKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :api_keys do |t|
      t.string :public_id, null: false
      t.string :name, null: false
      t.string :token_digest, null: false
      t.string :token_prefix, null: false
      t.string :scopes, null: false, default: "read"
      # Optional user the key acts as, for permission-scoped access. When null the
      # key is treated as an anonymous/guest reader (only public content is exposed).
      t.bigint :user_id
      t.bigint :created_by_id
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :api_keys, :token_digest, unique: true
    add_index :api_keys, :public_id, unique: true
    add_index :api_keys, :token_prefix

    add_foreign_key :api_keys, :users, column: :user_id, on_delete: :nullify
    add_foreign_key :api_keys, :users, column: :created_by_id, on_delete: :nullify
  end
end
