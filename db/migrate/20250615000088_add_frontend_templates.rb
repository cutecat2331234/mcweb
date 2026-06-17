# frozen_string_literal: true

class AddFrontendTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :frontend_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.string :version, null: false, default: "1.0.0"
      t.jsonb :scopes, null: false, default: []
      t.jsonb :manifest, null: false, default: {}
      t.string :checksum, null: false, default: ""
      t.string :status, null: false, default: "pending"
      t.string :installed_path
      t.text :error_message

      t.timestamps
    end

    add_index :frontend_templates, :key, unique: true
    add_index :frontend_templates, :status
  end
end
