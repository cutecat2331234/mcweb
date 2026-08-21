# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddCommerceSelfServiceLifecycles < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  def up
    add_column :store_refunds, :withdrawn_at, :datetime, if_not_exists: true
    add_reference :store_refunds, :withdrawn_by, index: false, if_not_exists: true
    ensure_foreign_key :store_refunds, :users, column: :withdrawn_by_id

    add_column :store_reviews, :deleted_at, :datetime, if_not_exists: true

    add_column :store_product_questions, :deleted_at, :datetime, if_not_exists: true
    add_column :store_product_questions, :edited_at, :datetime, if_not_exists: true

    add_column :store_product_answers, :status, :string,
      null: false, default: "published", if_not_exists: true
    add_column :store_product_answers, :deleted_at, :datetime, if_not_exists: true
    add_column :store_product_answers, :edited_at, :datetime, if_not_exists: true

    ensure_check_constraint :store_refunds,
      "status IN ('pending', 'approved', 'rejected', 'failed', 'completed', 'withdrawn')",
      name: "store_refunds_status_valid"
    ensure_check_constraint :store_reviews,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_reviews_status_valid"
    ensure_check_constraint :store_product_questions,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_questions_status_valid"
    ensure_check_constraint :store_product_answers,
      "status IN ('published', 'hidden', 'deleted')",
      name: "store_product_answers_status_valid"
  end

  def down
    remove_check_constraint :store_product_answers, name: "store_product_answers_status_valid", if_exists: true
    remove_check_constraint :store_product_questions, name: "store_product_questions_status_valid", if_exists: true
    remove_check_constraint :store_reviews, name: "store_reviews_status_valid", if_exists: true
    remove_check_constraint :store_refunds, name: "store_refunds_status_valid", if_exists: true

    remove_column :store_product_answers, :edited_at, if_exists: true
    remove_column :store_product_answers, :deleted_at, if_exists: true
    remove_column :store_product_answers, :status, if_exists: true

    remove_column :store_product_questions, :edited_at, if_exists: true
    remove_column :store_product_questions, :deleted_at, if_exists: true
    remove_column :store_reviews, :deleted_at, if_exists: true

    remove_foreign_key :store_refunds, column: :withdrawn_by_id, if_exists: true
    remove_reference :store_refunds, :withdrawn_by, if_exists: true
    remove_column :store_refunds, :withdrawn_at, if_exists: true
  end
end
