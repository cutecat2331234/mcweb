# frozen_string_literal: true

class AddForumPostsCountToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :forum_posts_count, :integer, null: false, default: 0

    # Backfill the denormalized counter from existing posts.
    execute <<~SQL.squish
      UPDATE users SET forum_posts_count = (
        SELECT COUNT(*) FROM forum_posts WHERE forum_posts.user_id = users.id
      )
    SQL
  end

  def down
    remove_column :users, :forum_posts_count
  end
end
