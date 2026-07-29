# frozen_string_literal: true

class AddTotpRecoveryToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :totp_recovery_token_digest, :string
    add_column :users, :totp_recovery_sent_at, :datetime

    add_index :users, :totp_recovery_token_digest,
              unique: true,
              where: "totp_recovery_token_digest IS NOT NULL",
              name: "index_users_on_totp_recovery_token_digest"
  end
end
