# frozen_string_literal: true

class AddRevisionsToCommerceUserContent < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :store_reviews, :lock_version, :integer, null: false, default: 0
    add_column :store_product_questions, :lock_version, :integer, null: false, default: 0
    add_column :store_product_answers, :lock_version, :integer, null: false, default: 0

    add_check_constraint :store_reviews,
      "lock_version >= 0",
      name: "store_reviews_lock_version_nonnegative",
      validate: false
    add_check_constraint :store_product_questions,
      "lock_version >= 0",
      name: "store_product_questions_lock_version_nonnegative",
      validate: false
    add_check_constraint :store_product_answers,
      "lock_version >= 0",
      name: "store_product_answers_lock_version_nonnegative",
      validate: false

    validate_check_constraint :store_reviews, name: "store_reviews_lock_version_nonnegative"
    validate_check_constraint :store_product_questions, name: "store_product_questions_lock_version_nonnegative"
    validate_check_constraint :store_product_answers, name: "store_product_answers_lock_version_nonnegative"
  end

  def down
    remove_check_constraint :store_product_answers, name: "store_product_answers_lock_version_nonnegative"
    remove_check_constraint :store_product_questions, name: "store_product_questions_lock_version_nonnegative"
    remove_check_constraint :store_reviews, name: "store_reviews_lock_version_nonnegative"

    remove_column :store_product_answers, :lock_version
    remove_column :store_product_questions, :lock_version
    remove_column :store_reviews, :lock_version
  end
end
