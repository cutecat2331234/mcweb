# frozen_string_literal: true

class AddForumProfilePosts < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_profile_posts do |t|
      t.references :profile_user, null: false, foreign_key: { to_table: :users }, index: false
      t.references :user, null: false, foreign_key: true # author
      t.text :body, null: false
      t.string :status, null: false, default: "published"
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :forum_profile_posts, %i[profile_user_id created_at]

    create_table :forum_profile_post_comments do |t|
      t.references :profile_post, null: false, foreign_key: { to_table: :forum_profile_posts }, index: false
      t.references :user, null: false, foreign_key: true # author
      t.text :body, null: false
      t.string :status, null: false, default: "published"
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :forum_profile_post_comments, %i[profile_post_id created_at]
  end
end
