# frozen_string_literal: true

class AddForumPmPolicyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_pm_policy, :string, null: false, default: "everyone"
  end
end
