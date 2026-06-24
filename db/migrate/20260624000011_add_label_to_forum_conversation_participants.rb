# frozen_string_literal: true

class AddLabelToForumConversationParticipants < ActiveRecord::Migration[8.1]
  def change
    add_column :forum_conversation_participants, :label, :string
  end
end
