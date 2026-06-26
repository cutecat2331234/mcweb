# frozen_string_literal: true

class AddAutoDismissToNotifications < ActiveRecord::Migration[8.1]
  def change
    add_column :notifications, :auto_dismiss, :boolean, null: false, default: false
  end
end
