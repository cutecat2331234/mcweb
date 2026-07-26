# frozen_string_literal: true

class OptimizeCommunityQueryPlans < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  PUBLISHED_REGULAR_POST = <<~SQL.squish.freeze
    deleted_at IS NULL AND status = 'published' AND post_type = 'regular'
  SQL

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :forum_topics,
      :title,
      using: :gin,
      opclass: :gin_trgm_ops,
      where: "deleted_at IS NULL AND status = 'published' AND unlisted = false AND archived_at IS NULL",
      name: :idx_forum_topics_suggest_title_trgm,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :users,
      %i[username display_name],
      using: :gin,
      opclass: { username: :gin_trgm_ops, display_name: :gin_trgm_ops },
      where: "status = 'active'",
      name: :idx_users_suggest_names_trgm,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :forum_tags,
      %i[name slug],
      using: :gin,
      opclass: { name: :gin_trgm_ops, slug: :gin_trgm_ops },
      name: :idx_forum_tags_suggest_names_trgm,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :forum_sections,
      %i[name slug],
      using: :gin,
      opclass: { name: :gin_trgm_ops, slug: :gin_trgm_ops },
      name: :idx_forum_sections_suggest_names_trgm,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :forum_posts,
      %i[created_at forum_topic_id],
      where: PUBLISHED_REGULAR_POST,
      name: :idx_forum_posts_top_window,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :forum_posts,
      %i[forum_topic_id floor_number],
      where: PUBLISHED_REGULAR_POST,
      name: :idx_forum_posts_unread_floor,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :notifications,
      %i[user_id created_at],
      order: { created_at: :desc },
      name: :idx_notifications_user_created,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :notifications,
      %i[user_id notification_type created_at],
      order: { created_at: :desc },
      name: :idx_notifications_user_type_created,
      algorithm: :concurrently,
      if_not_exists: true

    add_index :notifications,
      %i[user_id created_at notification_type],
      order: { created_at: :desc },
      where: "read_at IS NULL",
      name: :idx_notifications_unread_user_created,
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :notifications,
      name: :idx_notifications_unread_user_created,
      algorithm: :concurrently,
      if_exists: true
    remove_index :notifications,
      name: :idx_notifications_user_type_created,
      algorithm: :concurrently,
      if_exists: true
    remove_index :notifications,
      name: :idx_notifications_user_created,
      algorithm: :concurrently,
      if_exists: true
    remove_index :forum_posts,
      name: :idx_forum_posts_unread_floor,
      algorithm: :concurrently,
      if_exists: true
    remove_index :forum_posts,
      name: :idx_forum_posts_top_window,
      algorithm: :concurrently,
      if_exists: true
    remove_index :forum_sections,
      name: :idx_forum_sections_suggest_names_trgm,
      algorithm: :concurrently,
      if_exists: true
    remove_index :forum_tags,
      name: :idx_forum_tags_suggest_names_trgm,
      algorithm: :concurrently,
      if_exists: true
    remove_index :users,
      name: :idx_users_suggest_names_trgm,
      algorithm: :concurrently,
      if_exists: true
    remove_index :forum_topics,
      name: :idx_forum_topics_suggest_title_trgm,
      algorithm: :concurrently,
      if_exists: true
  end
end
