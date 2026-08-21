# frozen_string_literal: true

class AddCommerceSelfServiceLifecycles < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :store_refunds, :withdrawn_at, :datetime
    add_reference :store_refunds, :withdrawn_by, index: false
    add_foreign_key :store_refunds, :users,
      column: :withdrawn_by_id,
      validate: false

    add_column :store_reviews, :deleted_at, :datetime

    add_column :store_product_questions, :deleted_at, :datetime
    add_column :store_product_questions, :edited_at, :datetime

    add_column :store_product_answers, :status, :string, null: false, default: "published"
    add_column :store_product_answers, :deleted_at, :datetime
    add_column :store_product_answers, :edited_at, :datetime

    add_check_constraint :store_refunds,
      "status IN ('pending', 'approved', 'rejected', 'failed', 'completed', 'withdrawn')",
      name: "store_refunds_status_valid",
      validate: false
    add_check_constraint :store_reviews,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_reviews_status_valid",
      validate: false
    add_check_constraint :store_product_questions,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_questions_status_valid",
      validate: false
    add_check_constraint :store_product_answers,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_answers_status_valid",
      validate: false

    validate_foreign_key :store_refunds, :users, column: :withdrawn_by_id
    validate_check_constraint :store_refunds, name: "store_refunds_status_valid"
    validate_check_constraint :store_reviews, name: "store_reviews_status_valid"
    validate_check_constraint :store_product_questions, name: "store_product_questions_status_valid"
    validate_check_constraint :store_product_answers, name: "store_product_answers_status_valid"
  end

  def down
    remove_check_constraint :store_product_answers, name: "store_product_answers_status_valid"
    remove_check_constraint :store_product_questions, name: "store_product_questions_status_valid"
    remove_check_constraint :store_reviews, name: "store_reviews_status_valid"
    remove_check_constraint :store_refunds, name: "store_refunds_status_valid"

    remove_column :store_product_answers, :edited_at
    remove_column :store_product_answers, :deleted_at
    remove_column :store_product_answers, :status

    remove_column :store_product_questions, :edited_at
    remove_column :store_product_questions, :deleted_at
    remove_column :store_reviews, :deleted_at

    remove_foreign_key :store_refunds, column: :withdrawn_by_id
    remove_reference :store_refunds, :withdrawn_by
    remove_column :store_refunds, :withdrawn_at
  end
end
