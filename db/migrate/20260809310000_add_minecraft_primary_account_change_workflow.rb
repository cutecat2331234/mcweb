# frozen_string_literal: true

class AddMinecraftPrimaryAccountChangeWorkflow < ActiveRecord::Migration[8.1]
  REQUEST_STATUSES = %w[pending approved rejected expired cancelled].freeze
  CHANGE_SOURCES = %w[player_immediate staff_approval administrator_override].freeze

  def change
    create_table :minecraft_primary_account_change_requests do |table|
      table.references :user, null: false, foreign_key: true
      table.references :target_identity_link,
                       null: false,
                       foreign_key: { to_table: :minecraft_identity_links }
      table.references :source_identity_link,
                       foreign_key: { to_table: :minecraft_identity_links }
      table.references :requested_by, null: false, foreign_key: { to_table: :users }
      table.references :decided_by, foreign_key: { to_table: :users }
      table.string :status, null: false, default: "pending"
      table.string :policy_snapshot, null: false, default: "staff_approval"
      table.string :idempotency_key_digest, null: false, limit: 64
      table.text :request_reason, null: false
      table.text :decision_reason
      table.datetime :requested_at, null: false
      table.datetime :expires_at, null: false
      table.datetime :resolved_at
      table.datetime :applied_at
      table.integer :lock_version, null: false, default: 0
      table.timestamps
    end

    add_index :minecraft_primary_account_change_requests,
              %i[user_id idempotency_key_digest],
              unique: true,
              name: "idx_mc_primary_requests_idempotency"
    add_index :minecraft_primary_account_change_requests,
              %i[user_id status requested_at],
              name: "idx_mc_primary_requests_user_status"
    add_index :minecraft_primary_account_change_requests,
              %i[target_identity_link_id status],
              name: "idx_mc_primary_requests_target_status"
    add_index :minecraft_primary_account_change_requests,
              :user_id,
              unique: true,
              where: "status = 'pending'",
              name: "idx_mc_primary_requests_one_pending"

    add_check_constraint :minecraft_primary_account_change_requests,
                         "status IN (#{quoted_values(REQUEST_STATUSES)})",
                         name: "mc_primary_requests_status"
    add_check_constraint :minecraft_primary_account_change_requests,
                         "policy_snapshot = 'staff_approval'",
                         name: "mc_primary_requests_policy"
    add_check_constraint :minecraft_primary_account_change_requests,
                         "idempotency_key_digest ~ '^[0-9a-f]{64}$'",
                         name: "mc_primary_requests_digest"
    add_check_constraint :minecraft_primary_account_change_requests,
                         "BTRIM(request_reason) <> ''",
                         name: "mc_primary_requests_reason"
    add_check_constraint :minecraft_primary_account_change_requests,
                         "expires_at > requested_at",
                         name: "mc_primary_requests_expiry"
    add_check_constraint :minecraft_primary_account_change_requests,
                         "source_identity_link_id IS NULL OR source_identity_link_id <> target_identity_link_id",
                         name: "mc_primary_requests_distinct_links"
    add_check_constraint :minecraft_primary_account_change_requests,
                         request_resolution_shape,
                         name: "mc_primary_requests_resolution_shape"

    create_table :minecraft_primary_account_change_events do |table|
      table.references :user, null: false, foreign_key: true
      table.references :from_identity_link,
                       foreign_key: { to_table: :minecraft_identity_links }
      table.references :to_identity_link,
                       null: false,
                       foreign_key: { to_table: :minecraft_identity_links }
      table.references :actor, null: false, foreign_key: { to_table: :users }
      table.references :primary_account_change_request,
                       foreign_key: { to_table: :minecraft_primary_account_change_requests }
      table.string :change_source, null: false
      table.string :idempotency_key_digest, null: false, limit: 64
      table.text :reason
      table.boolean :counts_for_cooldown, null: false, default: true
      table.datetime :changed_at, null: false
      table.timestamps
    end

    add_index :minecraft_primary_account_change_events,
              %i[user_id changed_at],
              name: "idx_mc_primary_events_user_changed"
    add_index :minecraft_primary_account_change_events,
              %i[user_id idempotency_key_digest],
              unique: true,
              name: "idx_mc_primary_events_idempotency"
    add_index :minecraft_primary_account_change_events,
              :primary_account_change_request_id,
              unique: true,
              where: "primary_account_change_request_id IS NOT NULL",
              name: "idx_mc_primary_events_request"

    add_check_constraint :minecraft_primary_account_change_events,
                         "change_source IN (#{quoted_values(CHANGE_SOURCES)})",
                         name: "mc_primary_events_source"
    add_check_constraint :minecraft_primary_account_change_events,
                         "idempotency_key_digest ~ '^[0-9a-f]{64}$'",
                         name: "mc_primary_events_digest"
    add_check_constraint :minecraft_primary_account_change_events,
                         "from_identity_link_id IS NULL OR from_identity_link_id <> to_identity_link_id",
                         name: "mc_primary_events_distinct_links"
    add_check_constraint :minecraft_primary_account_change_events,
                         "change_source <> 'administrator_override' OR BTRIM(COALESCE(reason, '')) <> ''",
                         name: "mc_primary_events_admin_reason"
  end

  private

  def quoted_values(values)
    values.map { |value| connection.quote(value) }.join(", ")
  end

  def request_resolution_shape
    <<~SQL.squish
      (status = 'pending' AND resolved_at IS NULL AND applied_at IS NULL AND decided_by_id IS NULL)
      OR
      (status = 'approved' AND resolved_at IS NOT NULL AND applied_at IS NOT NULL AND decided_by_id IS NOT NULL)
      OR
      (status = 'rejected' AND resolved_at IS NOT NULL AND applied_at IS NULL AND decided_by_id IS NOT NULL
        AND BTRIM(COALESCE(decision_reason, '')) <> '')
      OR
      (status = 'expired' AND resolved_at IS NOT NULL AND applied_at IS NULL AND decided_by_id IS NULL)
      OR
      (status = 'cancelled' AND resolved_at IS NOT NULL AND applied_at IS NULL)
    SQL
  end
end
