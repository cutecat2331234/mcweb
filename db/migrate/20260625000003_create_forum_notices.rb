# frozen_string_literal: true

class CreateForumNotices < ActiveRecord::Migration[8.1]
  def change
    create_table :forum_notices do |t|
      t.string :title, null: false
      t.text :message, null: false
      t.string :style, null: false, default: "info"
      t.string :audience, null: false, default: "everyone"
      t.boolean :active, null: false, default: true
      t.boolean :dismissible, null: false, default: true
      t.integer :min_trust_level
      t.integer :max_trust_level
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :forum_notices, [ :active, :position ]
    add_column :users, :dismissed_forum_notice_ids, :jsonb, null: false, default: []
  end
end
