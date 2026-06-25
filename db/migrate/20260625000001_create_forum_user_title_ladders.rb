# frozen_string_literal: true

class CreateForumUserTitleLadders < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_user_title_ladders do |t|
      t.integer :min_posts, null: false, default: 0
      t.string :title, null: false
      t.timestamps
    end

    add_index :forum_user_title_ladders, :min_posts
  end
end
