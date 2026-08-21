# frozen_string_literal: true

class AddCommerceSelfServiceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :store_refunds, :withdrawn_by_id,
      algorithm: :concurrently,
      name: "index_store_refunds_on_withdrawn_by_id"
    add_index :store_product_answers, [ :store_product_question_id, :status ],
      algorithm: :concurrently,
      name: "index_store_product_answers_on_question_and_status"
  end

  def down
    remove_index :store_product_answers,
      algorithm: :concurrently,
      name: "index_store_product_answers_on_question_and_status"
    remove_index :store_refunds,
      algorithm: :concurrently,
      name: "index_store_refunds_on_withdrawn_by_id"
  end
end
