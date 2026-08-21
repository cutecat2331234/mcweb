# frozen_string_literal: true

require Rails.root.join("lib/mcweb/migrations/resumable_postgres")

class AddRevisionsToCommerceUserContent < ActiveRecord::Migration[8.1]
  include Mcweb::Migrations::ResumablePostgres

  disable_ddl_transaction!

  def up
    add_column :store_reviews, :lock_version, :integer,
      null: false, default: 0, if_not_exists: true
    add_column :store_product_questions, :lock_version, :integer,
      null: false, default: 0, if_not_exists: true
    add_column :store_product_answers, :lock_version, :integer,
      null: false, default: 0, if_not_exists: true

    ensure_check_constraint :store_reviews,
      "lock_version >= 0",
      name: "store_reviews_lock_version_nonnegative"
    ensure_check_constraint :store_product_questions,
      "lock_version >= 0",
      name: "store_product_questions_lock_version_nonnegative"
    ensure_check_constraint :store_product_answers,
      "lock_version >= 0",
      name: "store_product_answers_lock_version_nonnegative"
  end

  def down
    remove_check_constraint :store_product_answers, name: "store_product_answers_lock_version_nonnegative", if_exists: true
    remove_check_constraint :store_product_questions, name: "store_product_questions_lock_version_nonnegative", if_exists: true
    remove_check_constraint :store_reviews, name: "store_reviews_lock_version_nonnegative", if_exists: true

    remove_column :store_product_answers, :lock_version, if_exists: true
    remove_column :store_product_questions, :lock_version, if_exists: true
    remove_column :store_reviews, :lock_version, if_exists: true
  end
end
