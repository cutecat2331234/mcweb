# frozen_string_literal: true

class AddPermissionVersionToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :permission_version, :bigint, null: false, default: 0
    add_check_constraint :users,
                         "permission_version >= 0",
                         name: "users_permission_version_nonnegative"
  end
end
