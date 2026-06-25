# frozen_string_literal: true

class AddStarredAtToForumConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_conversation_participants, :starred_at, :datetime
  end
end
