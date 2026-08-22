# frozen_string_literal: true

class AddAccountClosureResultsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :account_closure_results, :jsonb, null: false, default: {}
  end
end
