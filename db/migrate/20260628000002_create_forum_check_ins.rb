# frozen_string_literal: true

class CreateForumCheckIns < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_check_ins do |t|
      t.bigint :user_id, null: false
      t.date :checked_on, null: false
      t.integer :streak, null: false, default: 1
      t.integer :points_awarded, null: false, default: 0
      t.timestamps
    end

    # One check-in per user per calendar day. The unique index also gives
    # DB-level protection against a concurrent double-submit (the service
    # rescues RecordNotUnique). It doubles as the lookup index for
    # "today" / "yesterday" streak queries.
    add_index :forum_check_ins, [ :user_id, :checked_on ], unique: true,
              name: "idx_forum_check_ins_user_date"

    add_foreign_key :forum_check_ins, :users
  end
end
