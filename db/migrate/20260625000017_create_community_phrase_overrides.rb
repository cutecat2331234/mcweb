# frozen_string_literal: true

class CreateCommunityPhraseOverrides < ActiveRecord::Migration[8.1]
  def change
    create_table :community_phrase_overrides do |t|
      t.string :locale, null: false
      t.string :key, null: false
      t.text :value, null: false, default: ""
      t.timestamps
    end

    add_index :community_phrase_overrides, [ :locale, :key ], unique: true
  end
end
