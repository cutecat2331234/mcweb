# frozen_string_literal: true

class AddRound78Features < ActiveRecord::Migration[8.1]
  def change
    change_table :forum_saved_searches, bulk: true do |t|
      t.string :webhook_url
    end
  end
end
