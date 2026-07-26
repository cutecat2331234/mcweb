# frozen_string_literal: true

class MarkDeveloperModeCredentials < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :developer_mode_email_verified, :boolean, default: false, null: false
    add_column :users, :developer_mode_relaxed_password, :boolean, default: false, null: false
    add_index :users,
      %i[developer_mode_email_verified developer_mode_relaxed_password],
      name: "index_users_on_developer_mode_credentials"
  end
end
