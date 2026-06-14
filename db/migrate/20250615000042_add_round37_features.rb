# frozen_string_literal: true

class AddRound37Features < ActiveRecord::Migration[8.0]
  def change
    add_column :forum_sections, :topic_template, :text

    create_table :forum_staff_notes do |t|
      t.references :user, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.timestamps
    end
  end
end
