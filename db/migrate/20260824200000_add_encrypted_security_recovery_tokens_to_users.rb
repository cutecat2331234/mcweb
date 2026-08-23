# frozen_string_literal: true

class AddEncryptedSecurityRecoveryTokensToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_reset_token_ciphertext, :text
    add_column :users, :totp_recovery_token_ciphertext, :text
  end
end
