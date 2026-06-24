# frozen_string_literal: true

class CreateForumMessageDrafts < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_message_drafts do |t|
      t.bigint :user_id, null: false
      t.bigint :forum_conversation_id, null: false
      t.text :body, null: false, default: ""

      t.timestamps
    end

    add_index :forum_message_drafts, [ :user_id, :forum_conversation_id ], unique: true, name: "index_forum_message_drafts_on_user_and_conversation"
    add_index :forum_message_drafts, :forum_conversation_id
  end
end
