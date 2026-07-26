# frozen_string_literal: true

class MarkDeveloperModeSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :developer_mode, :boolean, default: false, null: false
    add_index :sessions, :developer_mode
  end
end
