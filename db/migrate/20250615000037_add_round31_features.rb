# frozen_string_literal: true

class AddRound31Features < ActiveRecord::Migration[8.0]
  def change
    add_reference :store_products, :forum_topic, foreign_key: { to_table: :forum_topics }, index: true
    add_column :store_products, :changelog_notified_version, :string

    add_reference :store_reviews, :forum_post, foreign_key: { to_table: :forum_posts }, index: true

    add_reference :store_product_questions, :store_order_item, foreign_key: true, index: true
  end
end
