# frozen_string_literal: true

class AddRound109Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_user_field_definitions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :field_type, null: false, default: "text"
      t.text :description
      t.text :choices
      t.integer :sort_order, default: 0, null: false
      t.string :visibility, null: false, default: "public"
      t.boolean :required, default: false, null: false
      t.boolean :show_on_registration, default: false, null: false
      t.boolean :show_on_profile, default: true, null: false
      t.boolean :editable_by_user, default: true, null: false
      t.boolean :active, default: true, null: false
      t.timestamps
    end
    add_index :forum_user_field_definitions, :key, unique: true

    create_table :forum_user_field_values do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_user_field_definition, null: false, foreign_key: true
      t.text :value
      t.timestamps
    end
    add_index :forum_user_field_values,
              %i[user_id forum_user_field_definition_id],
              unique: true,
              name: "index_forum_user_field_values_on_user_and_definition"
  end
end
