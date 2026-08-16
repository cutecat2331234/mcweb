# frozen_string_literal: true

class AddMinecraftIdentityUnlinkSafety < ActiveRecord::Migration[8.1]
  def change
    add_column :minecraft_identity_links, :lock_version, :integer, null: false, default: 0
    add_column :minecraft_identity_links, :unlink_idempotency_key_digest, :string, limit: 64

    add_index :minecraft_identity_links,
              %i[user_id unlink_idempotency_key_digest],
              unique: true,
              where: "unlink_idempotency_key_digest IS NOT NULL",
              name: "idx_mc_identity_links_unlink_idempotency"
    add_check_constraint :minecraft_identity_links,
                         "unlink_idempotency_key_digest IS NULL OR " \
                           "unlink_idempotency_key_digest ~ '^[0-9a-f]{64}$'",
                         name: "mc_identity_links_unlink_digest_format"
    add_check_constraint :minecraft_identity_links,
                         "lock_version >= 0",
                         name: "mc_identity_links_lock_version"
  end
end
