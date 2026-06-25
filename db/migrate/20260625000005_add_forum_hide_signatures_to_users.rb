# frozen_string_literal: true

class AddForumHideSignaturesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_hide_signatures, :boolean, null: false, default: false
  end
end
