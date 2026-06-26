# frozen_string_literal: true

class CreateCommunityForumPages < ActiveRecord::Migration[8.1]
  def change
    create_table :community_forum_pages do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.text :body, null: false, default: ""
      t.boolean :show_in_nav, null: false, default: false
      t.string :nav_label
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :community_forum_pages, :slug, unique: true
    add_index :community_forum_pages, [ :show_in_nav, :position ]
  end
end
