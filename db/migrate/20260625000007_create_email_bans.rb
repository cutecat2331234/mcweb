# frozen_string_literal: true

class CreateEmailBans < ActiveRecord::Migration[8.1]
  def change
    create_table :email_bans do |t|
      t.string :pattern, null: false
      t.text :reason
      t.datetime :expires_at
      t.bigint :banned_by_id
      t.timestamps
    end

    add_index :email_bans, :pattern, unique: true
    add_index :email_bans, :banned_by_id
    add_foreign_key :email_bans, :users, column: :banned_by_id
  end
end
