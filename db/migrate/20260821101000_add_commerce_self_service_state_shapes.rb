# frozen_string_literal: true

class AddCommerceSelfServiceStateShapes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_check_constraint :store_refunds,
      "(status = 'withdrawn' AND withdrawn_at IS NOT NULL AND withdrawn_by_id IS NOT NULL) OR " \
        "(status <> 'withdrawn' AND withdrawn_at IS NULL AND withdrawn_by_id IS NULL)",
      name: "store_refunds_withdrawn_shape",
      validate: false
    add_check_constraint :store_reviews,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_reviews_deleted_shape",
      validate: false
    add_check_constraint :store_product_questions,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_product_questions_deleted_shape",
      validate: false
    add_check_constraint :store_product_answers,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_product_answers_deleted_shape",
      validate: false

    validate_check_constraint :store_refunds, name: "store_refunds_withdrawn_shape"
    validate_check_constraint :store_reviews, name: "store_reviews_deleted_shape"
    validate_check_constraint :store_product_questions, name: "store_product_questions_deleted_shape"
    validate_check_constraint :store_product_answers, name: "store_product_answers_deleted_shape"
  end

  def down
    remove_check_constraint :store_product_answers, name: "store_product_answers_deleted_shape"
    remove_check_constraint :store_product_questions, name: "store_product_questions_deleted_shape"
    remove_check_constraint :store_reviews, name: "store_reviews_deleted_shape"
    remove_check_constraint :store_refunds, name: "store_refunds_withdrawn_shape"
  end
end
