# frozen_string_literal: true

class AddRound84Features < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_watch_email_mode, :string, null: false, default: "instant"
  end
end
