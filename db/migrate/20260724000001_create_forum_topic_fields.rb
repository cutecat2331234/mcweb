# frozen_string_literal: true

class CreateForumTopicFields < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_topic_field_definitions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.string :field_type, null: false, default: "text"
      t.text :description
      t.text :choices
      t.integer :sort_order, null: false, default: 0
      t.string :display_location, null: false, default: "before_message"
      t.boolean :required, null: false, default: false
      t.boolean :editable_by_user, null: false, default: true
      t.boolean :active, null: false, default: true
      t.jsonb :section_ids, null: false, default: []
      t.jsonb :editable_group_ids, null: false, default: []
      t.string :owner_plugin_id
      t.timestamps
    end

    add_index :forum_topic_field_definitions, :key, unique: true
    add_index :forum_topic_field_definitions, %i[active sort_order]
    add_index :forum_topic_field_definitions, :owner_plugin_id

    create_table :forum_topic_field_values do |t|
      t.references :forum_topic, null: false, foreign_key: { to_table: :forum_topics }
      t.references :forum_topic_field_definition, null: false,
        foreign_key: { to_table: :forum_topic_field_definitions }
      t.text :value, null: false
      t.timestamps
    end

    add_index :forum_topic_field_values,
      %i[forum_topic_id forum_topic_field_definition_id],
      unique: true,
      name: "idx_forum_topic_field_values_unique"
  end
end
