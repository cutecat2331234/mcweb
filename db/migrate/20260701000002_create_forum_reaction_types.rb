# frozen_string_literal: true

class CreateForumReactionTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_reaction_types do |t|
      t.string :emoji, null: false
      t.string :name, null: false
      t.integer :score, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :forum_reaction_types, :emoji, unique: true
    add_index :forum_reaction_types, [ :active, :position ]
  end
end
