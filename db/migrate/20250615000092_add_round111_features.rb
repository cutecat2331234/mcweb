# frozen_string_literal: true

class AddRound111Features < ActiveRecord::Migration[8.0]
  def change
    create_table :forum_section_moderators do |t|
      t.references :forum_section, null: false, foreign_key: { to_table: :forum_sections }
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :forum_section_moderators, %i[forum_section_id user_id], unique: true
  end
end
