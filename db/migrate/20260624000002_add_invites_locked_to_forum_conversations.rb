# frozen_string_literal: true

class AddInvitesLockedToForumConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_conversations, :invites_locked, :boolean, null: false, default: false
  end
end
