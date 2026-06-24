# frozen_string_literal: true

class AddDeletedAtToForumMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_messages, :deleted_at, :datetime
    add_index :forum_messages, :deleted_at
  end
end
