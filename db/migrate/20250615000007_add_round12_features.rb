# frozen_string_literal: true

class AddRound12Features < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :forum_title, :string
    add_column :store_carts, :abandoned_reminder_sent_at, :datetime

    create_table :forum_censored_words do |t|
      t.string :word, null: false
      t.string :replacement, null: false, default: "***"
      t.timestamps
    end
    add_index :forum_censored_words, :word, unique: true
  end
end
