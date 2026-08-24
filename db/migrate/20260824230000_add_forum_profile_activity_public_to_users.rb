# frozen_string_literal: true

class AddForumProfileActivityPublicToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_profile_activity_public, :boolean, default: false, null: false
  end
end
