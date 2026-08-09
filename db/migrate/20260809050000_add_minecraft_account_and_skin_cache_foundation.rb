# frozen_string_literal: true

class AddMinecraftAccountAndSkinCacheFoundation < ActiveRecord::Migration[8.0]
  def change
    add_column :minecraft_identity_links, :primary_account, :boolean, default: false, null: false

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE minecraft_identity_links
          SET primary_account = TRUE
          WHERE id IN (
            SELECT DISTINCT ON (user_id) id
            FROM minecraft_identity_links
            WHERE unlinked_at IS NULL
            ORDER BY user_id, linked_at ASC, id ASC
          )
        SQL
      end
    end

    add_index :minecraft_identity_links,
              :user_id,
              unique: true,
              where: "unlinked_at IS NULL AND primary_account = TRUE",
              name: "idx_mc_identity_links_one_primary_per_user"

    change_table :minecraft_player_identities, bulk: true do |table|
      table.datetime :skin_cached_at
      table.datetime :skin_refresh_attempted_at
      table.datetime :skin_refresh_failed_at
      table.string :skin_refresh_error_code
      table.string :skin_texture_sha256, limit: 64
      table.string :cape_texture_sha256, limit: 64
      table.integer :skin_cache_version, default: 0, null: false
    end

    add_index :minecraft_player_identities,
              %i[superseded_at skin_cached_at],
              name: "idx_mc_player_identities_skin_cache_due"

    create_table :minecraft_skin_refresh_requests do |table|
      table.references :player_identity,
                       null: false,
                       foreign_key: { to_table: :minecraft_player_identities }
      table.references :requested_by, foreign_key: { to_table: :users }
      table.string :idempotency_key_digest, limit: 64, null: false
      table.string :trigger, default: "scheduled", null: false
      table.string :status, default: "pending", null: false
      table.string :error_code
      table.boolean :cache_changed, default: false, null: false
      table.datetime :started_at
      table.datetime :completed_at
      table.timestamps
    end

    add_index :minecraft_skin_refresh_requests,
              %i[player_identity_id idempotency_key_digest],
              unique: true,
              name: "idx_mc_skin_refresh_requests_idempotency"
    add_index :minecraft_skin_refresh_requests,
              %i[status started_at],
              name: "idx_mc_skin_refresh_requests_recovery"
  end
end
