# frozen_string_literal: true

class CreateCommunityHelpArticles < ActiveRecord::Migration[8.1]
  def change
    create_table :community_help_articles do |t|
      t.string :title, null: false
      t.string :slug, null: false
      t.string :category, null: false, default: "general"
      t.text :body, null: false, default: ""
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: true
      t.timestamps
    end

    add_index :community_help_articles, :slug, unique: true
    add_index :community_help_articles, [ :category, :position ]
  end
end
