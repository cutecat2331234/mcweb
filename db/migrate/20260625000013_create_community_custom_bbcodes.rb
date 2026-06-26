# frozen_string_literal: true

class CreateCommunityCustomBbcodes < ActiveRecord::Migration[8.1]
  def change
    create_table :community_custom_bbcodes do |t|
      t.string :tag, null: false
      t.text :replacement, null: false, default: ""
      t.string :sample
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :community_custom_bbcodes, :tag, unique: true
  end
end
