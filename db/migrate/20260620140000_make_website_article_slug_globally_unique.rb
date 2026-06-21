# frozen_string_literal: true

class MakeWebsiteArticleSlugGloballyUnique < ActiveRecord::Migration[8.0]
  def up
    remove_index :website_articles, column: %i[article_type slug], if_exists: true
    add_index :website_articles, :slug, unique: true
  end

  def down
    remove_index :website_articles, :slug, if_exists: true
    add_index :website_articles, %i[article_type slug], unique: true
  end
end
