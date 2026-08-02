# frozen_string_literal: true

class AddLifecycleToForumSections < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :archived_at, :datetime
    add_reference :forum_sections, :archived_by, foreign_key: { to_table: :users }
    add_column :forum_sections, :archived_reason, :text

    add_index :forum_sections, [ :archived_at, :position ]
  end
end
