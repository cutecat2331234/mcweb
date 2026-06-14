# frozen_string_literal: true

class AddRound15Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_conversations, :title, :string
    add_column :forum_conversations, :is_group, :boolean, default: false, null: false
    add_reference :forum_conversations, :creator, foreign_key: { to_table: :users }

    add_column :forum_tags, :description, :text
    add_column :forum_tags, :staff_only, :boolean, default: false, null: false
  end
end
