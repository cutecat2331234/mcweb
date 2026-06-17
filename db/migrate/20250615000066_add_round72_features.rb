# frozen_string_literal: true

class AddRound72Features < ActiveRecord::Migration[8.1]
  def change
    change_table :forum_saved_searches, bulk: true do |t|
      t.boolean :notify_daily, default: false, null: false
      t.datetime :last_notified_at
    end
  end
end
