# frozen_string_literal: true

class AddForumProfileViewsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_profile_views, :integer, null: false, default: 0
  end
end
