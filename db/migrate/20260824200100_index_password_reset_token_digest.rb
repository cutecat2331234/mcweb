# frozen_string_literal: true

class IndexPasswordResetTokenDigest < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_index :users,
              :password_reset_token_digest,
              unique: true,
              where: "password_reset_token_digest IS NOT NULL",
              algorithm: :concurrently,
              name: "idx_users_password_reset_token_digest"
  end

  def down
    remove_index :users,
                 name: "idx_users_password_reset_token_digest",
                 algorithm: :concurrently
  end
end
