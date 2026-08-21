# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddCommerceSelfServiceIndexes < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  def up
    ensure_concurrent_index :store_refunds, :withdrawn_by_id,
      name: "index_store_refunds_on_withdrawn_by_id"
    ensure_concurrent_index :store_product_answers, [ :store_product_question_id, :status ],
      name: "index_store_product_answers_on_question_and_status"
  end

  def down
    remove_concurrent_index :store_product_answers,
      name: "index_store_product_answers_on_question_and_status"
    remove_concurrent_index :store_refunds,
      name: "index_store_refunds_on_withdrawn_by_id"
  end
end
