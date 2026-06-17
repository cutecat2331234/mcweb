# frozen_string_literal: true

class AddRound91Features < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_saved_searches, :notify_in_app, :boolean, default: true, null: false
    add_column :forum_conversation_participants, :muted_at, :datetime
    add_index :forum_conversation_participants, :muted_at
  end
end
