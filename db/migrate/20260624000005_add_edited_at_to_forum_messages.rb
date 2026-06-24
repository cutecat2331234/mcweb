# frozen_string_literal: true

class AddEditedAtToForumMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_messages, :edited_at, :datetime
  end
end
