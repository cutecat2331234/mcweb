# frozen_string_literal: true

class AddRound32Features < ActiveRecord::Migration[8.0]
  def change
    create_table :store_product_answer_helpful_votes do |t|
      t.references :store_product_answer, null: false, foreign_key: true, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.timestamps
    end

    add_index :store_product_answer_helpful_votes,
              [ :store_product_answer_id, :user_id ],
              unique: true,
              name: "index_answer_helpful_votes_on_answer_and_user"
  end
end
