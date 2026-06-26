# frozen_string_literal: true

class CreateCommunityForumThemes < ActiveRecord::Migration[8.1]
  def change
    create_table :community_forum_themes do |t|
      t.string :name, null: false
      t.string :primary_color
      t.string :accent_color
      t.boolean :is_default, null: false, default: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :community_forum_themes, :is_default
  end
end
