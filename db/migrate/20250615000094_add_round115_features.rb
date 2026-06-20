# frozen_string_literal: true

class AddRound115Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_reply_drafts, :attachment_ids, :jsonb, null: false, default: []
  end
end
