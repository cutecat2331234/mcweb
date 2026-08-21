# frozen_string_literal: true

class AddEncryptedEmailVerificationTokenToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_verification_token_ciphertext, :text
  end
end
