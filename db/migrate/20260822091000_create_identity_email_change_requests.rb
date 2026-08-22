# frozen_string_literal: true

class CreateIdentityEmailChangeRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :identity_email_change_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :initiating_session, foreign_key: { to_table: :sessions, on_delete: :nullify }
      t.string :original_email, null: false
      t.string :requested_email, null: false
      t.boolean :original_email_verified, null: false
      t.datetime :original_email_verified_at
      t.text :confirmation_token_ciphertext
      t.string :confirmation_token_digest, null: false
      t.text :revocation_token_ciphertext
      t.string :revocation_token_digest, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :requested_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :confirmed_at
      t.datetime :revert_expires_at
      t.datetime :reverted_at
      t.integer :lock_version, null: false, default: 0
      t.timestamps

      t.index :confirmation_token_digest, unique: true,
              name: "idx_identity_email_changes_confirmation_token"
      t.index :revocation_token_digest, unique: true,
              name: "idx_identity_email_changes_revocation_token"
      t.index :user_id, unique: true, where: "status = 'pending'",
              name: "idx_identity_email_changes_one_pending_per_user"
      t.index "LOWER(requested_email)", unique: true, where: "status = 'pending'",
              name: "idx_identity_email_changes_one_pending_target"
      t.index [ :status, :expires_at ], name: "idx_identity_email_changes_expiry"
      t.check_constraint "status IN ('pending', 'confirmed', 'revoked', 'superseded', 'expired')",
                         name: "chk_identity_email_changes_status"
    end
  end
end
