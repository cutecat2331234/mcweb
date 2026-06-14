# frozen_string_literal: true

class AddCommunityBookmarksAndTags < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_bookmarks do |t|
      t.references :user, null: false, foreign_key: true
      t.references :forum_topic, null: false, foreign_key: true
      t.timestamps
    end
    add_index :forum_bookmarks, [ :user_id, :forum_topic_id ], unique: true

    create_table :forum_tags do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.timestamps
    end
    add_index :forum_tags, :slug, unique: true

    create_table :forum_topic_tags do |t|
      t.references :forum_topic, null: false, foreign_key: true
      t.references :forum_tag, null: false, foreign_key: true
      t.timestamps
    end
    add_index :forum_topic_tags, [ :forum_topic_id, :forum_tag_id ], unique: true
  end
end
