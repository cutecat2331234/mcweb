# frozen_string_literal: true

class AddForumRound11Features < ActiveRecord::Migration[8.1]
  def up
    add_column :forum_sections, :prefixes, :jsonb, default: [], null: false
    add_column :forum_topics, :prefix, :string

    execute <<~SQL.squish
      CREATE INDEX index_forum_topics_on_title_tsvector
      ON forum_topics USING gin(to_tsvector('simple', coalesce(title, '')));
      CREATE INDEX index_forum_posts_on_body_tsvector
      ON forum_posts USING gin(to_tsvector('simple', coalesce(body, '')));
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX IF EXISTS index_forum_topics_on_title_tsvector;
      DROP INDEX IF EXISTS index_forum_posts_on_body_tsvector;
    SQL

    remove_column :forum_topics, :prefix
    remove_column :forum_sections, :prefixes
  end
end
