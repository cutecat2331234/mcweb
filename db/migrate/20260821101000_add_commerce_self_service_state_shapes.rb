# frozen_string_literal: true

class AddCommerceSelfServiceStateShapes < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :store_refunds,
      "(status = 'withdrawn' AND withdrawn_at IS NOT NULL AND withdrawn_by_id IS NOT NULL) OR " \
        "(status <> 'withdrawn' AND withdrawn_at IS NULL AND withdrawn_by_id IS NULL)",
      name: "store_refunds_withdrawn_shape"
    add_check_constraint :store_reviews,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_reviews_deleted_shape"
    add_check_constraint :store_product_questions,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_product_questions_deleted_shape"
    add_check_constraint :store_product_answers,
      "(status = 'deleted' AND deleted_at IS NOT NULL) OR (status <> 'deleted' AND deleted_at IS NULL)",
      name: "store_product_answers_deleted_shape"
  end
end
