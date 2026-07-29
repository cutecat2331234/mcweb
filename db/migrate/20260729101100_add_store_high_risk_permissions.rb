# frozen_string_literal: true

class AddStoreHighRiskPermissions < ActiveRecord::Migration[8.1]
  PERMISSIONS = {
    "store.credit.read" => [
      "View member store credit",
      "View member store-credit balances and adjustment history"
    ],
    "store.entitlements.read" => [
      "View member entitlements",
      "View manually managed memberships and digital entitlements"
    ],
    "store.entitlements.grant" => [
      "Grant member entitlements",
      "Manually grant memberships and digital entitlements"
    ],
    "store.entitlements.revoke" => [
      "Revoke member entitlements",
      "Manually revoke memberships and digital entitlements"
    ],
    "store.orders.mark_paid" => [
      "Mark orders paid",
      "Manually mark eligible orders as paid"
    ],
    "store.orders.mark_fulfilled" => [
      "Mark orders fulfilled",
      "Manually mark eligible orders as fulfilled"
    ],
    "store.orders.cancel" => [
      "Cancel orders",
      "Manually cancel pending orders"
    ]
  }.freeze

  LEGACY_GRANTS = {
    "store.credit.read" => "store.credit.adjust",
    "store.entitlements.read" => "store.products.manage",
    "store.entitlements.grant" => "store.products.manage",
    "store.entitlements.revoke" => "store.products.manage",
    "store.orders.mark_paid" => "store.orders.refund",
    "store.orders.mark_fulfilled" => "store.orders.refund",
    "store.orders.cancel" => "store.orders.refund"
  }.freeze

  def up
    PERMISSIONS.each do |key, (name, description)|
      execute <<~SQL.squish
        INSERT INTO permissions (key, name, category, description, created_at, updated_at)
        VALUES (
          #{connection.quote(key)},
          #{connection.quote(name)},
          'store',
          #{connection.quote(description)},
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        )
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    LEGACY_GRANTS.each do |new_key, legacy_key|
      execute <<~SQL.squish
        INSERT INTO role_permissions (role_id, permission_id, created_at, updated_at)
        SELECT role_permissions.role_id, new_permission.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM role_permissions
        INNER JOIN permissions legacy_permission
          ON legacy_permission.id = role_permissions.permission_id
        CROSS JOIN permissions new_permission
        WHERE legacy_permission.key = #{connection.quote(legacy_key)}
          AND new_permission.key = #{connection.quote(new_key)}
        ON CONFLICT (role_id, permission_id) DO NOTHING
      SQL
    end
  end

  def down
    quoted_keys = PERMISSIONS.keys.map { |key| connection.quote(key) }.join(", ")
    execute <<~SQL.squish
      DELETE FROM role_permissions
      WHERE permission_id IN (SELECT id FROM permissions WHERE key IN (#{quoted_keys}))
    SQL
    execute <<~SQL.squish
      DELETE FROM permissions WHERE key IN (#{quoted_keys})
    SQL
  end
end
