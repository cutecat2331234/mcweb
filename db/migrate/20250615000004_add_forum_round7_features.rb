# frozen_string_literal: true

class AddForumRound7Features < ActiveRecord::Migration[8.1]
  def change
    add_reference :forum_posts, :parent_post, foreign_key: { to_table: :forum_posts }, index: true

    add_column :forum_topics, :slow_mode_seconds, :integer
    add_column :forum_topics, :wiki, :boolean, default: false, null: false
    add_reference :forum_topics, :solved_post, foreign_key: { to_table: :forum_posts }, index: true

    add_column :users, :bio, :text
  end
end
