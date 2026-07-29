# frozen_string_literal: true

class ExpandDeveloperModeTooling < ActiveRecord::Migration[8.0]
  PERSONAS = %w[owner moderator member].freeze

  def change
    add_column :users, :developer_mode_persona, :string
    add_index :users,
      :developer_mode_persona,
      unique: true,
      where: "developer_mode_persona IS NOT NULL",
      name: "idx_users_unique_developer_mode_persona"
    add_check_constraint :users,
      "developer_mode_persona IS NULL OR developer_mode_persona IN ('owner', 'moderator', 'member')",
      name: "users_developer_mode_persona"

    create_table :developer_mode_runtime_states do |t|
      t.boolean :enabled, null: false, default: false
      t.string :profile
      t.string :configuration_digest, null: false
      t.jsonb :configuration_summary, null: false, default: {}
      t.datetime :observed_at, null: false

      t.timestamps
    end
  end
end
