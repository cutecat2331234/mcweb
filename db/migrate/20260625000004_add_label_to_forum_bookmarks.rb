# frozen_string_literal: true

class AddLabelToForumBookmarks < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_bookmarks, :label, :string
    add_index :forum_bookmarks, [ :user_id, :label ]
  end
end
