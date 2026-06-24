# frozen_string_literal: true

class AddForumDndUntilToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :forum_dnd_until, :datetime
  end
end
