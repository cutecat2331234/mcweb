# frozen_string_literal: true

class CreateCommunitySmilies < ActiveRecord::Migration[8.1]
  def change
    create_table :community_smilies do |t|
      t.string :code, null: false
      t.string :emoji, null: false
      t.string :title
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :community_smilies, :code, unique: true
  end
end
