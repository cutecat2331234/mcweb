# frozen_string_literal: true

class AddRound92Features < ActiveRecord::Migration[8.1]
  def change
    add_column :store_orders, :payment_reminder_sent_at, :datetime
    add_index :store_orders, :payment_reminder_sent_at
  end
end
