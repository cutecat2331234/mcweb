# frozen_string_literal: true

class AddRound86Features < ActiveRecord::Migration[8.1]
  def up
    add_column :forum_search_histories, :fingerprint, :string
    change_column_null :forum_saved_search_webhook_deliveries, :saved_search_id, true

    Community::SearchHistory.reset_column_information
    Community::SearchHistory.find_each do |history|
      fingerprint = Community::SearchHistoryFingerprint.generate(query: history.query, filters: history.filters)
      history.update_column(:fingerprint, fingerprint)
    end

    add_index :forum_search_histories, %i[user_id fingerprint], unique: true
  end

  def down
    remove_index :forum_search_histories, column: %i[user_id fingerprint]
    remove_column :forum_search_histories, :fingerprint
    change_column_null :forum_saved_search_webhook_deliveries, :saved_search_id, false
  end
end
