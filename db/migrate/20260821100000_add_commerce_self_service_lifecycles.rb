# frozen_string_literal: true

class AddCommerceSelfServiceLifecycles < ActiveRecord::Migration[8.1]
  def change
    add_column :store_refunds, :withdrawn_at, :datetime
    add_reference :store_refunds, :withdrawn_by, foreign_key: { to_table: :users }

    add_column :store_reviews, :deleted_at, :datetime

    add_column :store_product_questions, :deleted_at, :datetime
    add_column :store_product_questions, :edited_at, :datetime

    add_column :store_product_answers, :status, :string, null: false, default: "published"
    add_column :store_product_answers, :deleted_at, :datetime
    add_column :store_product_answers, :edited_at, :datetime

    add_check_constraint :store_refunds,
      "status IN ('pending', 'approved', 'rejected', 'failed', 'completed', 'withdrawn')",
      name: "store_refunds_status_valid"
    add_check_constraint :store_reviews,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_reviews_status_valid"
    add_check_constraint :store_product_questions,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_questions_status_valid"
    add_check_constraint :store_product_answers,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_answers_status_valid"
    add_index :store_product_answers, [ :store_product_question_id, :status ],
      name: "index_store_product_answers_on_question_and_status"
  end
end
