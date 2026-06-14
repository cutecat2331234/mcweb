# frozen_string_literal: true

class AddRound17Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_post_edits, :reason, :string

    create_table :store_review_helpful_votes do |t|
      t.bigint :store_review_id, null: false
      t.bigint :user_id, null: false
      t.timestamps
    end
    add_index :store_review_helpful_votes, [ :store_review_id, :user_id ], unique: true, name: "index_review_helpful_votes_on_review_and_user"
    add_foreign_key :store_review_helpful_votes, :store_reviews, column: :store_review_id
    add_foreign_key :store_review_helpful_votes, :users
  end
end
